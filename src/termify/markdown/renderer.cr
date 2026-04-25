require "../ansi"

module Termify
  module Markdown
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
    enum BlockMode
      Normal
      CodeFence
    end

    class Renderer < IO
      # -- patterns ----------------------------------------------------------
      private HEADING         = /^([#]{1,6}) (.*)/
      private UNORDERED_LIST  = /^\s*[-*+] (.*)/
      private ORDERED_LIST    = /^\s*\d+\. (.*)/
      private HORIZONTAL_RULE = /^\s*(-{3,}|\*{3,}|_{3,})\s*$/
      private INLINE_HTML     = /<\/?[a-zA-Z][^>]*>/
      private BLOCK_HTML      = /^\s*<[^>]+>\s*$/

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
        dispatch_block(line)
      end

      # Handles a line while in CodeFence mode. Returns true if consumed.
      private def process_fence_line(line : String) : Bool
        return false unless @block_mode.code_fence?
        if line.starts_with?(@fence_marker)
          @block_mode = BlockMode::Normal
        else
          emit_raw(Element::CodeBlock, line)
        end
        true
      end

      private def fence_start?(line : String) : Bool
        line.starts_with?("```") || line.starts_with?("~~~")
      end

      private def dispatch_block(line : String) : Nil
        if m = line.match(HEADING)
          emit_styled(heading_element(m[1].size), m[2])
        elsif fence_start?(line)
          @fence_marker = line[0, 3]
          @block_mode = BlockMode::CodeFence
        elsif line.starts_with?("> ")
          emit_styled(Element::Blockquote, line[2..])
        elsif line.starts_with?(">")
          emit_styled(Element::Blockquote, line[1..])
        elsif horizontal_rule?(line)
          emit_styled(Element::HorizontalRule, line)
        elsif m = line.match(UNORDERED_LIST)
          emit_styled(Element::ListItem, m[1])
        elsif m = line.match(ORDERED_LIST)
          emit_styled(Element::ListItem, m[1])
        elsif BLOCK_HTML.matches?(line)
          emit_raw(Element::BlockHtml, line.strip)
        elsif line.empty?
          @io << '\n'
        else
          emit_styled(Element::Paragraph, line)
        end
      end

      private def emit_styled(element : Element, text : String) : Nil
        style = @stylesheet[element]
        ansi = style.to_ansi
        prefix = style.prefix || ""
        reset = ansi.empty? ? "" : ANSI::RESET
        @io << ansi << prefix << render_inline(text, style) << reset << '\n'
      end

      # Emits *text* verbatim -- no inline parsing. Used for code fence body
      # lines where delimiters are content, not markup.
      private def emit_raw(element : Element, text : String) : Nil
        style = @stylesheet[element]
        ansi = style.to_ansi
        prefix = style.prefix || ""
        reset = ansi.empty? ? "" : ANSI::RESET
        @io << ansi << prefix << text << reset << '\n'
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
