require "./style_sheet"
require "./table_renderer"
require "./code_renderer"
require "./blockquote_io"

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
        @fence_indent = 0
        @table_rows = [] of Array(String)
        @table_col_alignments = [] of TableRenderer::ColumnAlignment
        @code_renderer = nil.as(CodeRenderer?)
        @quote_renderer = nil.as(Renderer?)
        @list_stack = [] of NamedTuple(indent: Int32, ordered: Bool, counter: Int32, content_indent: Int32)
        @list_pending_blank = false
        @current_block = nil.as(BlockElement?)

        # Need to track if current line is empty so we can
        # ensure blank lines don't accumulate, and ensure that
        # block newline-based margin (via newline_before/newline_after)
        # merging works properly with blank lines.
        @current_line_empty = false
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
        close_quote_renderer
        flush_table if @block_mode.table?
        close_block(nil)
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
        end
        return if process_quote_line(line)
        return if process_table_line(line)
        dispatch_block(line)
      end

      # Handles a line while in CodeFence mode. Returns true if consumed.
      # Handles a line while in CodeFence mode. Returns true if consumed.
      # When inside a list, strips the item's content indent before checking
      # the fence marker so indented fences work correctly.
      private def process_fence_line(line : String) : Bool
        return false unless @block_mode.code_fence?
        # Only strip @fence_indent spaces if the line actually starts with them.
        # Body lines in a top-level fence have no indent; this avoids slicing
        # into content when a fence opens with leading spaces.
        stripped = (@fence_indent > 0 && line.starts_with?(" " * @fence_indent)) ? line[@fence_indent..] : line
        if stripped.starts_with?(@fence_marker)
          @code_renderer.try(&.close)
          @code_renderer = nil
          @block_mode = BlockMode::Normal
        else
          open_block(BlockElement::CodeBlock)
          @code_renderer.try(&.feed(stripped))
          @current_line_empty = false
        end
        true
      end

      # Handles a line while in Table mode, or detects a new table. Returns
      # true if the line was consumed, false to fall through to dispatch_block.
      private def process_table_line(line : String) : Bool
        if @block_mode.table?
          if TABLE_ROW.matches?(line)
            buffer_table_row(line, @stylesheet[BlockElement::Table])
            return true
          else
            flush_table
            return false
          end
        elsif TABLE_ROW.matches?(line)
          @block_mode = BlockMode::Table
          buffer_table_row(line, @stylesheet[BlockElement::Table])
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
            when .ends_with?(':') then TableRenderer::ColumnAlignment::Right
            when .includes?(':')  then TableRenderer::ColumnAlignment::Middle
            else                       TableRenderer::ColumnAlignment::Left
            end
          end
        else
          cells = cells.map do |cell|
            String.build do |io|
              emit_styled(BlockElement::Table, render_inline(cell, style), io, chomp: true)
            end
          end
          @table_rows << cells
        end
      end

      # Renders buffered rows via TableRenderer and resets table state.
      # Returns leading spaces matching current list content indent, or "".
      private def list_visual_indent : String
        @list_stack.empty? ? "" : " " * @list_stack.last[:content_indent]
      end

      private def flush_table : Nil
        close_block(nil)
        unless @table_rows.empty?
          indent = @list_stack.empty? ? 0 : @list_stack.last[:content_indent]
          TableRenderer.render(@table_rows, @table_col_alignments, @io, indent)
          @current_line_empty = false
        end
        @table_rows.clear
        @block_mode = BlockMode::Normal
      end

      private def fence_start?(line : String) : Bool
        stripped = line.lstrip
        return false if line.size - stripped.size > 3
        stripped.starts_with?("```") || stripped.starts_with?("~~~")
      end

      # Handles a line that may belong to a blockquote. Returns true if consumed.
      # A > prefix routes to the child renderer; a blank line is forwarded to
      # the child if one is active; any other line closes the child and returns
      # false so normal dispatch can proceed.
      private def process_quote_line(line : String) : Bool
        if line.starts_with?("> ")
          open_quote_renderer
          @quote_renderer.try(&.feed(line[2..] + "\n"))
          true
        elsif line.starts_with?(">")
          open_quote_renderer
          @quote_renderer.try(&.feed(line[1..] + "\n"))
          true
        else
          # Blank lines and non-quote lines both close any deeper nesting and
          # fall through. This ensures blank lines get prefix decoration at the
          # correct depth rather than being forwarded one level too deep.
          close_quote_renderer
          false
        end
      end

      # Opens a child Renderer writing through a BlockquoteIO prefix wrapper.
      # Idempotent -- a second call while the child is active is a no-op.
      private def open_quote_renderer : Nil
        return if @quote_renderer
        open_block(BlockElement::Blockquote)
        style = @stylesheet[BlockElement::Blockquote]
        ansi = style.to_ansi
        prefix = style.line_prefix || ""
        # Emit EL+RESET suffix only on the outermost BlockquoteIO.
        # Inner BIOs must use an empty suffix so the bg color stays active
        # past their \n and the outermost EL fires while bg is still set.
        # An inner RESET before the outer EL would clear the bg and cause
        # the outer EL to fill with the terminal default instead of the bg color.
        is_nested = @io.is_a?(BlockquoteIO)
        suffix = (style.bg && !ansi.empty? && !is_nested) ? ANSI::ERASE_LINE + ANSI::RESET : ""
        wrapped_io = BlockquoteIO.new(@io, list_visual_indent + ansi + prefix, suffix)
        @quote_renderer = Renderer.new(wrapped_io, @stylesheet)
      end

      # Closes and flushes the child renderer, syncing blank-line state back
      # to the parent so margin logic stays correct for the next block.
      private def close_quote_renderer : Nil
        if r = @quote_renderer
          r.close
          @quote_renderer = nil
          @current_line_empty = r.@current_line_empty
        end
      end

      private def dispatch_block(line : String) : Nil
        if m = line.match(HEADING)
          emit_styled(heading_element(m[1].size), m[2])
        elsif fence_start?(line)
          fenced = line.lstrip
          @fence_marker = fenced[0, 3]
          @fence_indent = line.size - fenced.size
          language = fenced[3..].strip
          @code_renderer = CodeRenderer.new(
            language,
            @stylesheet.code_block_style,
            @io,
            list_visual_indent
          )
          @block_mode = BlockMode::CodeFence
        elsif horizontal_rule?(line)
          emit_styled(BlockElement::HorizontalRule, line)
        elsif list_line?(line)
          process_list_item(line)
        elsif BLOCK_HTML.matches?(line)
          emit_raw(BlockElement::BlockHtml, line.strip)
          @current_line_empty = false
        else
          emit_styled(BlockElement::Paragraph, line)
        end
      end

      # Called when the first line of a new semantic block arrives.
      # Closes the previous block (emitting newline_after if set), then
      # emits newline_before for the incoming block, OR-collapsed with
      # newline_after of the outgoing block so at most one blank line appears.
      private def open_block(element : BlockElement) : Nil
        return if @current_block == element
        unless @current_line_empty
          incoming = @stylesheet[element]
          outgoing_after = if prev = @current_block
                             @stylesheet[prev].newline_after?
                           else
                             false
                           end
          if outgoing_after || incoming.newline_before?
            @current_line_empty = true # sometimes we write an empty line, so remember that
            @io << '\n'
          end
        end
        @current_block = element
      end

      # Called when the current block is known to be finished (blank line,
      # close, exit_list, flush_table). Resets tracking; newline_after is
      # handled by open_block for the next block via OR-collapse, or by
      # close when the document ends.
      private def close_block(element : BlockElement?) : Nil
        if element.nil? && (prev = @current_block) && !@current_line_empty
          if @stylesheet[prev].newline_after?
            @current_line_empty = true # sometimes we write an empty line, so remember that
            @io << '\n'
          end
        end
        @current_block = element
      end

      private def emit_styled(element : BlockElement, text : String, io = @io, chomp = false) : Nil
        open_block(element) if io.same?(@io)

        return if text.empty? && @current_line_empty

        style = @stylesheet[element]
        ansi = style.to_ansi
        prefix = style.line_prefix || ""
        erase = (style.bg && !ansi.empty?) ? ANSI::ERASE_LINE : ""
        reset = ansi.empty? ? "" : ANSI::RESET
        list_indent = io.same?(@io) ? list_visual_indent : ""
        io << ansi << list_indent << prefix << render_inline(text, style) << erase << reset << style.line_suffix
        io << '\n' unless chomp

        # sometimes we write an empty line, so remember that
        @current_line_empty = text.empty?
      end

      # Emits *text* verbatim -- no inline parsing. Used for block HTML.
      private def emit_raw(element : BlockElement, text : String) : Nil
        open_block(element)
        style = @stylesheet[element]
        ansi = style.to_ansi
        prefix = style.line_prefix || ""
        erase = (style.bg && !ansi.empty?) ? ANSI::ERASE_LINE : ""
        reset = ansi.empty? ? "" : ANSI::RESET
        @io << ansi << list_visual_indent << prefix << text << erase << reset << '\n'
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
        inline_stack = [] of {InlineElement, String}
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
        block_style : Style, inline_stack : Array({InlineElement, String}),
      ) : Int32
        if j = find_char(chars, '`', i + 1)
          buf << @stylesheet[InlineElement::CodeInline].to_ansi
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
        block_style : Style, inline_stack : Array({InlineElement, String}),
      ) : Int32
        if m = chars[i..].join.match(INLINE_HTML)
          tag = m[0]
          buf << @stylesheet[InlineElement::HtmlTag].to_ansi
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
        block_style : Style, inline_stack : Array({InlineElement, String}),
      ) : Int32
        if close_bracket = find_char(chars, ']', i + 1)
          if chars[close_bracket + 1]? == '(' &&
             (close_paren = find_char(chars, ')', close_bracket + 2))
            link_text = chars[i + 1...close_bracket].join
            link_style = @stylesheet[InlineElement::Link]
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
        block_style : Style, inline_stack : Array({InlineElement, String}),
      ) : Int32
        if i + 1 < n && chars[i + 1] == '*'
          if inline_stack.any? { |entry| entry[0] == InlineElement::Bold }
            pop_inline(InlineElement::Bold, inline_stack)
            buf << replay_sequence(block_style, inline_stack)
          elsif find_two_chars(chars, '*', i + 2)
            seq = @stylesheet[InlineElement::Bold].to_ansi
            inline_stack << {InlineElement::Bold, seq}
            buf << seq
          else
            buf << "**"
          end
          i + 2
        else
          if inline_stack.any? { |entry| entry[0] == InlineElement::Italic }
            pop_inline(InlineElement::Italic, inline_stack)
            buf << replay_sequence(block_style, inline_stack)
          elsif find_single_star(chars, i + 1)
            seq = @stylesheet[InlineElement::Italic].to_ansi
            inline_stack << {InlineElement::Italic, seq}
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
        block_style : Style, inline_stack : Array({InlineElement, String}),
      ) : Int32
        if i + 1 < n && chars[i + 1] == '~'
          if inline_stack.any? { |entry| entry[0] == InlineElement::Strikethrough }
            pop_inline(InlineElement::Strikethrough, inline_stack)
            buf << replay_sequence(block_style, inline_stack)
          elsif find_two_chars(chars, '~', i + 2)
            seq = @stylesheet[InlineElement::Strikethrough].to_ansi
            inline_stack << {InlineElement::Strikethrough, seq}
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
        block_style : Style, inline_stack : Array({InlineElement, String}),
      ) : Int32
        prev_word = i > 0 && chars[i - 1].alphanumeric?
        next_word = i + 1 < n && chars[i + 1].alphanumeric?
        if prev_word && next_word
          buf << '_'
        elsif inline_stack.any? { |entry| entry[0] == InlineElement::Italic }
          pop_inline(InlineElement::Italic, inline_stack)
          buf << replay_sequence(block_style, inline_stack)
        elsif find_closing_underscore(chars, i + 1)
          seq = @stylesheet[InlineElement::Italic].to_ansi
          inline_stack << {InlineElement::Italic, seq}
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

      private def pop_inline(element : InlineElement, stack : Array({InlineElement, String})) : Nil
        idx = stack.rindex { |entry| entry[0] == element }
        stack.delete_at(idx) if idx
      end

      # Returns RESET + block_style ANSI + replay of all open inline sequences.
      # Emitted when closing an inline span so the composite style is restored.
      private def replay_sequence(block_style : Style, stack : Array({InlineElement, String})) : String
        ANSI::RESET + block_style.to_ansi + stack.map { |entry| entry[1] }.join
      end

      # -- block helpers -----------------------------------------------------
      private def heading_element(level : Int) : BlockElement
        case level
        when 1 then BlockElement::H1
        when 2 then BlockElement::H2
        when 3 then BlockElement::H3
        when 4 then BlockElement::H4
        when 5 then BlockElement::H5
        else        BlockElement::H6
        end
      end

      private def horizontal_rule?(line : String) : Bool
        !!(line =~ HORIZONTAL_RULE)
      end

      # -- list helpers -------------------------------------------------------

      # Returns true if *line* is an unordered or ordered list item.
      private def list_line?(line : String) : Bool
        UNORDERED_LIST.matches?(line) || ORDERED_LIST.matches?(line)
      end

      # Clears list nesting state. Called on any non-continuation, non-list line.
      # Blank lines within a list item are swallowed (loose list termination deferred).
      private def exit_list : Nil
        close_block(nil)
        @list_stack.clear
        @list_pending_blank = false
      end

      # Handles a line while a list is active. Returns true if consumed; false
      # if the list was exited and the line needs normal dispatch.
      private def handle_list_line(line : String) : Bool
        if line.empty?
          @list_pending_blank = true
          return true
        end

        pending = @list_pending_blank
        @list_pending_blank = false

        if list_line?(line)
          flush_table if @block_mode.table?
          process_list_item(line)
          true
        elsif list_continuation?(line)
          indent = line.size - line.lstrip.size
          dispatch_continuation(line.lstrip)
          # If the continuation opened a code fence, the line was already
          # lstripped before dispatch so @fence_indent was set to 0. Patch it
          # with the actual indent so process_fence_line can match the closing
          # marker correctly.
          @fence_indent = indent if @block_mode.code_fence?
          true
        else
          flush_table if @block_mode.table?
          exit_list
          @io << '\n' if pending
          false
        end
      end

      # Returns true if *line* has any positive indentation, making it a
      # continuation block of the current list item. list_line? is checked
      # first so actual list items are never misidentified as continuations.
      private def list_continuation?(line : String) : Bool
        line.size - line.lstrip.size > 0
      end

      # Dispatches a continuation line (already de-indented) through the normal
      # table and block pipeline, bypassing the list check.
      private def dispatch_continuation(line : String) : Nil
        return if process_quote_line(line)
        return if process_table_line(line)
        dispatch_block(line)
      end

      # Updates the list nesting stack for a new item at *indent*.
      private def process_list_item(line : String) : Nil
        indent, ordered, content, content_indent = parse_list_line(line)
        update_list_stack(indent, ordered, content_indent)
        emit_list_item(content, list_item_prefix(ordered))
      end

      # Parses indent, type, content text, and content column from a list line.
      private def parse_list_line(line : String) : {Int32, Bool, String, Int32}
        indent = line.size - line.lstrip.size
        ordered = ORDERED_LIST.matches?(line)
        content = ordered ? line.match!(ORDERED_LIST)[1] : line.match!(UNORDERED_LIST)[1]
        {indent, ordered, content, line.size - content.size}
      end

      # Updates the list nesting stack for a new item at *indent*.
      private def update_list_stack(indent : Int32, ordered : Bool, content_indent : Int32) : Nil
        if @list_stack.empty? || indent > @list_stack.last[:indent]
          push_list_level(indent, ordered, content_indent)
        elsif indent < @list_stack.last[:indent]
          while @list_stack.size > 1 && @list_stack.last[:indent] > indent
            @list_stack.pop
          end
          increment_counter(content_indent) if ordered
        elsif ordered != @list_stack.last[:ordered]
          @list_stack.pop
          push_list_level(indent, ordered, content_indent)
        else
          increment_counter(content_indent) if ordered
        end
      end

      # Pushes a new level onto the list stack.
      private def push_list_level(indent : Int32, ordered : Bool, content_indent : Int32) : Nil
        @list_stack << {indent: indent, ordered: ordered, counter: ordered ? 1 : 0, content_indent: content_indent}
      end

      # Increments the counter on the top stack entry, preserving all other fields.
      private def increment_counter(content_indent : Int32) : Nil
        last = @list_stack.pop
        @list_stack << {indent: last[:indent], ordered: last[:ordered], counter: last[:counter] + 1, content_indent: content_indent}
      end

      # Returns the prefix string for the current list depth and type.
      private def list_item_prefix(ordered : Bool) : String
        depth = @list_stack.size - 1
        if ordered
          "  " * depth + @list_stack.last[:counter].to_s + ". "
        else
          "  " * depth + BULLETS[depth % BULLETS.size] + " "
        end
      end

      # Emits one list item using ListItem stylesheet style but a dynamic prefix.
      private def emit_list_item(content : String, list_prefix : String) : Nil
        open_block(BlockElement::ListItem)
        style = @stylesheet[BlockElement::ListItem]
        ansi = style.to_ansi
        erase = (style.bg && !ansi.empty?) ? ANSI::ERASE_LINE : ""
        reset = ansi.empty? ? "" : ANSI::RESET
        @io << ansi << list_prefix << render_inline(content, style) << erase << reset << (style.line_suffix || "") << '\n'
        @current_line_empty = false
      end
    end
  end
end
