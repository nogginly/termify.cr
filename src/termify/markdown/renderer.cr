require "../ansi"
require "./table_renderer"

module Termify
  module Markdown
    enum BlockMode
      Normal
      CodeFence
      Table
    end

    # Streaming Markdown-to-ANSI renderer.
    #
    # Feed arbitrary chunks of Markdown text via #feed (or via the IO interface);
    # the renderer emits styled ANSI lines to *io* as soon as complete lines are
    # available. Call #close when the input stream is exhausted to flush any
    # remainder.
    #
    # Data flow:
    #   feed(chunk) -> @buf << chunk -> flush_complete_lines
    #                                     scan for \n
    #                                     process_line(each complete line)
    #                                     keep remainder in @buf
    #   close       -> flush_complete_lines -> process_line(remainder) if any
    #
    # IO contract
    # -----------
    # Renderer inherits IO for composability: any IO-accepting API (puts, <<,
    # pipe, etc.) can target a Renderer directly. write(Bytes) is the required
    # implementation point; it decodes the slice as UTF-8 and delegates to feed.
    # Caller guarantees valid UTF-8; no BOM handling is performed.
    # read(Bytes) always raises -- the renderer is write-only.
    # The renderer never closes @io; the caller owns the output IO lifecycle.

    class Renderer < IO
      # -- patterns ----------------------------------------------------------
      private HEADING         = /^([#]{1,6}) (.*)/
      private UNORDERED_LIST  = /^\s*[-*+] (.*)/
      private ORDERED_LIST    = /^\s*\d+\. (.*)/
      private HORIZONTAL_RULE = /^\s*(-{3,}|\*{3,}|_{3,})\s*$/
      private BULLETS         = ["*", "\u2013", "\u00b7"] # *, --, .
      private INLINE_HTML     = /<\/?[a-zA-Z][^>]*>/
      private BLOCK_HTML      = /^\s*<[^>]+>\s*$/

      # Two kinds of table row syntax
      #     | value | value ... |
      #       value | value | ...
      private TABLE_ROW = /^(\|.*\|)|(.*(\|.*)+)$/

      # Two kinds of table row separator syntax
      #     | ----- | -----| ... |
      #       ----- | ---- | ...
      private TABLE_SEPARATOR = /^(\|[\s|:-]+\|)|([\s|:-]+(\|[\s|:-]+)+)$/

      getter stylesheet : Stylesheet
      getter io : IO

      # -- IO abstract interface ---------------------------------------------
      # Decodes `slice` as UTF-8 Markdown and feeds it into the renderer.
      # Caller guarantees valid UTF-8.
      def write(slice : Bytes) : Nil
        feed(String.new(slice))
      end

      # Renderer is write-only; reading always raises.
      def read(slice : Bytes) : Int32
        raise IO::Error.new("Renderer is write-only")
      end

      # -- lifecycle ---------------------------------------------------------
      def initialize(@io : IO, @stylesheet : Stylesheet = Stylesheet.default)
        @closed = false
        @buf = String::Builder.new
        @block_mode = BlockMode::Normal
        @fence_marker = ""
        @table_rows = [] of Array(String)
        @table_col_alignments = [] of TableRenderer::ColumnAlignment
        @list_stack = [] of NamedTuple(indent: Int32, ordered: Bool, counter: Int32, content_indent: Int32)
        @list_pending_blank = false
      end

      # Accepts the next chunk of Markdown. May be any size -- a single byte
      # up to the entire document. Raises if called after #close.
      def feed(chunk : String) : Nil
        raise "Renderer is closed" if @closed
        @buf << chunk
        flush_complete_lines
      end

      # Flushes any buffered content and marks the renderer closed.
      # Idempotent: safe to call more than once.
      def close : Nil
        return if @closed
        @closed = true
        flush_complete_lines
        remainder = @buf.to_s
        process_line(remainder) unless remainder.empty?
        flush_table if @block_mode.table?
      end

      def closed? : Bool
        @closed
      end

      # -- private -----------------------------------------------------------
      # Drains every complete (newline-terminated) line from @buf, passing each
      # to process_line. Leaves the trailing partial line (possibly empty) in @buf.
      private def flush_complete_lines : Nil
        content = @buf.to_s
        @buf = String::Builder.new
        content.each_line(chomp: false) do |line|
          if line.ends_with?('\n')
            process_line(line.chomp)
          else
            @buf << line
          end
        end
      end

      # Dispatches one logical line to the appropriate block handler.
      private def process_line(line : String) : Nil
        return if process_fence_line(line)
        unless @list_stack.empty?
          return if handle_list_line(line)
          # handle_list_line returned false: list was exited, dispatch normally
        end
        return if process_table_line(line)
        dispatch_block(line)
      end

      # Handles a line while in CodeFence mode. Returns true if consumed.
      # When inside a list, strips the item's content indent before checking
      # the fence marker so indented fences work correctly.
      private def process_fence_line(line : String) : Bool
        return false unless @block_mode.code_fence?
        stripped = @list_stack.empty? ? line : strip_list_indent(line, @list_stack.last[:content_indent])
        if stripped.starts_with?(@fence_marker)
          @block_mode = BlockMode::Normal
        else
          emit_raw(Element::CodeBlock, stripped)
        end
        true
      end

      # Handles a line while in Table mode, or detects a new table. Returns
      # true if the line was consumed, false to fall through to dispatch_block.
      private def process_table_line(line : String) : Bool
        if @block_mode.table?
          if TABLE_ROW.matches?(line)
            buffer_table_row(line, @stylesheet[Element::Table])
            return true
          else
            flush_table
            return false
          end
        elsif TABLE_ROW.matches?(line)
          @block_mode = BlockMode::Table
          buffer_table_row(line, @stylesheet[Element::Table])
          return true
        end
        false
      end

      # Parses and buffers one table row; silently drops separator rows.
      private def buffer_table_row(line : String, style : Style) : Nil
        # trim first/last column separator
        line = line[1..-1] if line.starts_with?('|')
        line = line[0..-2] if line.ends_with?('|')
        cells = line.split("|").map(&.strip)

        if TABLE_SEPARATOR.matches?(line)
          @table_col_alignments = cells.map do |cell|
            case cell
            when .starts_with?(':') then TableRenderer::ColumnAlignment::Left
            when .ends_with?(':')   then TableRenderer::ColumnAlignment::Right
            else                         TableRenderer::ColumnAlignment::Middle
            end
          end
        else
          cells = cells.map do |cell|
            String.build do |io|
              emit_styled(Element::Table, render_inline(cell, style), io)
            end
          end
          @table_rows << cells
        end
      end

      # Returns leading spaces matching current list content indent, or "".
      private def list_visual_indent : String
        @list_stack.empty? ? "" : " " * @list_stack.last[:content_indent]
      end

      # Renders buffered rows via TableRenderer and resets table state.
      private def flush_table : Nil
        indent = @list_stack.empty? ? 0 : @list_stack.last[:content_indent]
        TableRenderer.render(@table_rows, @table_col_alignments, @io, indent) unless @table_rows.empty?
        @table_rows.clear
        @table_col_alignments.clear
        @block_mode = BlockMode::Normal
      end

      # Returns true if *line* is an unordered or ordered list item.
      private def list_line?(line : String) : Bool
        UNORDERED_LIST.matches?(line) || ORDERED_LIST.matches?(line)
      end

      # Clears list nesting state. Called on any non-continuation, non-list line.
      # Blank lines within a list item are swallowed (loose list termination deferred).
      private def exit_list : Nil
        @list_stack.clear
        @list_pending_blank = false
      end

      # Handles a line while a list is active. Returns true if the line was
      # consumed; false if the list was exited and the line needs normal dispatch.
      #
      # Blank lines are swallowed (set @list_pending_blank) rather than terminating
      # the list immediately, to support continuation blocks. The list exits only
      # when a non-blank, non-continuation, non-list line appears.
      private def handle_list_line(line : String) : Bool
        if line.empty?
          @list_pending_blank = true
          return true
        end

        pending = @list_pending_blank
        @list_pending_blank = false
        content_indent = @list_stack.last[:content_indent]

        if list_line?(line)
          flush_table if @block_mode.table?
          process_list_item(line)
          true
        elsif list_continuation?(line, content_indent)
          dispatch_continuation(strip_list_indent(line, content_indent))
          true
        else
          flush_table if @block_mode.table?
          exit_list
          @io << '\n' if pending
          false
        end
      end

      # Returns true if *line* has enough leading whitespace to be a continuation
      # block of the current list item (i.e. leading spaces >= content_indent).
      private def list_continuation?(line : String, content_indent : Int32) : Bool
        (line.size - line.lstrip.size) >= content_indent
      end

      # Strips exactly *n* leading characters from *line*.
      # Safe: if *line* is shorter than *n*, strips all leading whitespace instead.
      private def strip_list_indent(line : String, n : Int32) : String
        line.size >= n ? line[n..] : line.lstrip
      end

      # Dispatches a continuation line (already de-indented) through the normal
      # table and block pipeline, bypassing the list check.
      private def dispatch_continuation(line : String) : Nil
        return if process_table_line(line)
        dispatch_block(line)
      end

      # Updates @list_stack and emits one list item with a depth-aware prefix.
      # The stylesheet ListItem prefix is intentionally bypassed here -- depth
      # and bullet/counter are computed dynamically from the stack.
      private def process_list_item(line : String) : Nil
        indent = line.size - line.lstrip.size
        ordered = ORDERED_LIST.matches?(line)
        content = if ordered
                    line.match!(ORDERED_LIST)[1]
                  else
                    line.match!(UNORDERED_LIST)[1]
                  end
        content_indent = line.size - content.size

        if @list_stack.empty? || indent > @list_stack.last[:indent]
          # New deeper level -- push a fresh entry.
          @list_stack << {indent: indent, ordered: ordered, counter: ordered ? 1 : 0, content_indent: content_indent}
        elsif indent < @list_stack.last[:indent]
          # Returning to a shallower level -- pop until we match.
          while @list_stack.size > 1 && @list_stack.last[:indent] > indent
            @list_stack.pop
          end
          increment_counter(content_indent) if ordered
        else
          # Same level -- increment counter (no-op for unordered).
          if ordered != @list_stack.last[:ordered]
            # Type changed at same indent -- treat as a fresh level.
            @list_stack.pop
            @list_stack << {indent: indent, ordered: ordered, counter: ordered ? 1 : 0, content_indent: content_indent}
          else
            increment_counter(content_indent) if ordered
          end
        end

        depth = @list_stack.size - 1
        list_prefix = if ordered
                        "  " * depth + @list_stack.last[:counter].to_s + ". "
                      else
                        "  " * depth + BULLETS[depth % BULLETS.size] + " "
                      end
        emit_list_item(content, list_prefix)
      end

      # Increments the counter on the top stack entry, preserving all other fields.
      private def increment_counter(content_indent : Int32) : Nil
        last = @list_stack.pop
        @list_stack << {indent: last[:indent], ordered: last[:ordered], counter: last[:counter] + 1, content_indent: content_indent}
      end

      # Emits one list item using ListItem stylesheet style but a dynamic prefix.
      private def emit_list_item(content : String, list_prefix : String) : Nil
        style = @stylesheet[Element::ListItem]
        ansi = style.to_ansi
        reset = ansi.empty? ? "" : ANSI::RESET
        @io << ansi << list_prefix << render_inline(content, style) << reset << (style.suffix || "") << '\n'
      end

      private def fence_start?(line : String) : Bool
        stripped = line.lstrip
        return false if line.size - stripped.size > 3
        stripped.starts_with?("```") || stripped.starts_with?("~~~")
      end

      private def dispatch_block(line : String) : Nil
        if m = line.match(HEADING)
          emit_styled(heading_element(m[1].size), m[2])
        elsif fence_start?(line)
          @fence_marker = line.lstrip[0, 3]
          @block_mode = BlockMode::CodeFence
        elsif line.starts_with?("> ")
          emit_styled(Element::Blockquote, line[2..])
        elsif line.starts_with?(">")
          emit_styled(Element::Blockquote, line[1..])
        elsif horizontal_rule?(line)
          emit_styled(Element::HorizontalRule, line)
        elsif list_line?(line)
          process_list_item(line)
        elsif BLOCK_HTML.matches?(line)
          emit_raw(Element::BlockHtml, line.strip)
        elsif line.empty?
          @io << '\n'
        else
          emit_styled(Element::Paragraph, line)
        end
      end

      private def emit_styled(element : Element, text : String, io = @io) : Nil
        style = @stylesheet[element]
        ansi = style.to_ansi
        prefix = style.prefix || ""
        reset = ansi.empty? ? "" : ANSI::RESET
        list_indent = io.same?(@io) ? list_visual_indent : ""
        io << ansi << list_indent << prefix << render_inline(text, style) << reset << style.suffix << '\n'
      end

      # Emits *text* verbatim -- no inline parsing. Used for code fence body
      # lines where delimiters are content, not markup.
      private def emit_raw(element : Element, text : String) : Nil
        style = @stylesheet[element]
        ansi = style.to_ansi
        prefix = style.prefix || ""
        reset = ansi.empty? ? "" : ANSI::RESET
        @io << ansi << list_visual_indent << prefix << text << reset << '\n'
      end

      # Left-to-right inline scanner. Supported spans (in priority order):
      #
      #   `code`    -- CodeInline (highest priority, greedy, no nesting inside)
      #   [text](url) -- Link (underline + FG_BRIGHT_BLUE; URL suppressed)
      #   **text**  -- Bold
      #   ~~text~~  -- Strikethrough
      #   *text*    -- Italic
      #   _text_    -- Italic (mid-word underscores emitted as literals)
      private def render_inline(text : String, block_style : Style) : String
        buf = String::Builder.new
        inline_stack = [] of {Element, String}
        chars = text.chars
        i = 0
        n = chars.size
        while i < n
          c = chars[i]
          i = case c
              when '`' then scan_code_span(chars, i, buf, block_style, inline_stack)
              when '<' then scan_html_tag(chars, i, buf, block_style, inline_stack)
              when '[' then scan_link(chars, i, buf, block_style, inline_stack)
              when '*' then scan_star(chars, i, n, buf, block_style, inline_stack)
              when '~' then scan_tilde(chars, i, n, buf, block_style, inline_stack)
              when '_' then scan_underscore(chars, i, n, buf, block_style, inline_stack)
              else          buf << c; i + 1
              end
        end
        buf << replay_sequence(block_style, inline_stack) unless inline_stack.empty?
        buf.to_s
      end

      # -- inline character scanners -----------------------------------------
      # Each accepts the chars array and current index i; mutates `buf` and
      # `inline_stack`; returns the next index to resume from.

      private def scan_code_span(
        chars : Array(Char), i : Int32, buf : String::Builder,
        block_style : Style, inline_stack : Array({Element, String}),
      ) : Int32
        if j = find_char(chars, '`', i + 1)
          buf << @stylesheet[Element::CodeInline].to_ansi
          buf << chars[i + 1...j].join
          buf << replay_sequence(block_style, inline_stack)
          j + 1
        else
          buf << '`'
          i + 1
        end
      end

      # Inline HTML tag -- emitted verbatim in HtmlTag style.
      private def scan_html_tag(
        chars : Array(Char), i : Int32, buf : String::Builder,
        block_style : Style, inline_stack : Array({Element, String}),
      ) : Int32
        if m = chars[i..].join.match(INLINE_HTML)
          tag = m[0]
          buf << @stylesheet[Element::HtmlTag].to_ansi
          buf << tag
          buf << replay_sequence(block_style, inline_stack)
          i + tag.size
        else
          buf << chars[i]
          i + 1
        end
      end

      # Link span [text](url) -- URL suppressed; link text re-enters render_inline.
      private def scan_link(
        chars : Array(Char), i : Int32, buf : String::Builder,
        block_style : Style, inline_stack : Array({Element, String}),
      ) : Int32
        if close_bracket = find_char(chars, ']', i + 1)
          if chars[close_bracket + 1]? == '(' &&
             (close_paren = find_char(chars, ')', close_bracket + 2))
            link_text = chars[i + 1...close_bracket].join
            link_style = @stylesheet[Element::Link]
            buf << link_style.to_ansi
            buf << render_inline(link_text, link_style)
            buf << replay_sequence(block_style, inline_stack)
            close_paren + 1
          else
            buf << '['
            i + 1
          end
        else
          buf << '['
          i + 1
        end
      end

      # "*" -- bold (**) or italic (*), determined by whether next char is also "*".
      private def scan_star(
        chars : Array(Char), i : Int32, n : Int32, buf : String::Builder,
        block_style : Style, inline_stack : Array({Element, String}),
      ) : Int32
        if i + 1 < n && chars[i + 1] == '*'
          if inline_stack.any? { |entry| entry[0] == Element::Bold }
            pop_inline(Element::Bold, inline_stack)
            buf << replay_sequence(block_style, inline_stack)
          elsif find_two_chars(chars, '*', i + 2)
            seq = @stylesheet[Element::Bold].to_ansi
            inline_stack << {Element::Bold, seq}
            buf << seq
          else
            buf << "**"
          end
          i + 2
        else
          if inline_stack.any? { |entry| entry[0] == Element::Italic }
            pop_inline(Element::Italic, inline_stack)
            buf << replay_sequence(block_style, inline_stack)
          elsif find_single_star(chars, i + 1)
            seq = @stylesheet[Element::Italic].to_ansi
            inline_stack << {Element::Italic, seq}
            buf << seq
          else
            buf << '*'
          end
          i + 1
        end
      end

      # "~~" -- strikethrough. Lone "~" emitted as literal.
      private def scan_tilde(
        chars : Array(Char), i : Int32, n : Int32, buf : String::Builder,
        block_style : Style, inline_stack : Array({Element, String}),
      ) : Int32
        if i + 1 < n && chars[i + 1] == '~'
          if inline_stack.any? { |entry| entry[0] == Element::Strikethrough }
            pop_inline(Element::Strikethrough, inline_stack)
            buf << replay_sequence(block_style, inline_stack)
          elsif find_two_chars(chars, '~', i + 2)
            seq = @stylesheet[Element::Strikethrough].to_ansi
            inline_stack << {Element::Strikethrough, seq}
            buf << seq
          else
            buf << "~~"
          end
          i + 2
        else
          buf << '~'
          i + 1
        end
      end

      # "_" -- italic, with mid-word exemption (snake_case passes through).
      private def scan_underscore(
        chars : Array(Char), i : Int32, n : Int32, buf : String::Builder,
        block_style : Style, inline_stack : Array({Element, String}),
      ) : Int32
        prev_word = i > 0 && chars[i - 1].alphanumeric?
        next_word = i + 1 < n && chars[i + 1].alphanumeric?
        if prev_word && next_word
          buf << '_'
        elsif inline_stack.any? { |entry| entry[0] == Element::Italic }
          pop_inline(Element::Italic, inline_stack)
          buf << replay_sequence(block_style, inline_stack)
        elsif find_closing_underscore(chars, i + 1)
          seq = @stylesheet[Element::Italic].to_ansi
          inline_stack << {Element::Italic, seq}
          buf << seq
        else
          buf << '_'
        end
        i + 1
      end

      # -- inline scanner helpers --------------------------------------------
      private def find_char(chars : Array(Char), ch : Char, from : Int32) : Int32?
        i = from
        while i < chars.size
          return i if chars[i] == ch
          i += 1
        end
        nil
      end

      private def find_two_chars(chars : Array(Char), ch : Char, from : Int32) : Int32?
        i = from
        while i + 1 < chars.size
          return i if chars[i] == ch && chars[i + 1] == ch
          i += 1
        end
        nil
      end

      private def find_single_star(chars : Array(Char), from : Int32) : Int32?
        i = from
        while i < chars.size
          if chars[i] == '*'
            if i + 1 < chars.size && chars[i + 1] == '*'
              i += 2
            else
              return i
            end
          else
            i += 1
          end
        end
        nil
      end

      private def find_closing_underscore(chars : Array(Char), from : Int32) : Int32?
        i = from
        n = chars.size
        while i < n
          if chars[i] == '_'
            prev_word = i > 0 && chars[i - 1].alphanumeric?
            next_word = i + 1 < n && chars[i + 1].alphanumeric?
            return i unless prev_word && next_word
          end
          i += 1
        end
        nil
      end

      private def pop_inline(element : Element, stack : Array({Element, String})) : Nil
        idx = stack.rindex { |entry| entry[0] == element }
        stack.delete_at(idx) if idx
      end

      # Returns RESET + block_style ANSI + replay of all open inline sequences.
      # Emitted when closing an inline span so the composite style is restored.
      private def replay_sequence(block_style : Style, stack : Array({Element, String})) : String
        ANSI::RESET + block_style.to_ansi + stack.map { |entry| entry[1] }.join
      end

      # -- block helpers -----------------------------------------------------
      private def heading_element(level : Int) : Element
        case level
        when 1 then Element::H1
        when 2 then Element::H2
        when 3 then Element::H3
        when 4 then Element::H4
        when 5 then Element::H5
        else        Element::H6
        end
      end

      private def horizontal_rule?(line : String) : Bool
        !!(line =~ HORIZONTAL_RULE)
      end
    end
  end
end
