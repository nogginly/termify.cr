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
        if @block_mode.code_fence?
          if line.starts_with?(@fence_marker)
            @block_mode = BlockMode::Normal
          else
            emit_raw(Element::CodeBlock, line)
          end
          return
        end
        if m = line.match(HEADING)
          emit_styled(heading_element(m[1].size), m[2])
        elsif line.starts_with?("```") || line.starts_with?("~~~")
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
        out = String::Builder.new
        inline_stack = [] of {Element, String}
        chars = text.chars
        i = 0
        n = chars.size
        while i < n
          c = chars[i]
          # -- backtick: code span (highest priority, greedy) ----------------
          if c == '`'
            if j = find_char(chars, '`', i + 1)
              code_text = chars[i + 1...j].join
              out << @stylesheet[Element::CodeInline].to_ansi
              out << code_text
              out << replay_sequence(block_style, inline_stack)
              i = j + 1
            else
              out << '`'
              i += 1
            end
            # -- "<": inline HTML tag (dim red, shown verbatim) ----------------
            # Tags are preserved as-is to signal their presence; no rendering
            # is attempted. INLINE_HTML is kept as a constant for easy tuning.
          elsif c == '<'
            if m = chars[i..].join.match(INLINE_HTML)
              tag = m[0]
              out << @stylesheet[Element::HtmlTag].to_ansi
              out << tag
              out << replay_sequence(block_style, inline_stack)
              i += tag.size
            else
              out << c
              i += 1
            end
            # -- "[": link span [text](url) ------------------------------------
            # URL is suppressed; link text is rendered with Link style (underline
            # + FG_BRIGHT_BLUE) and passed through render_inline so bold/italic
            # inside link text works. Unmatched "[" emitted as literal.
          elsif c == '['
            if close_bracket = find_char(chars, ']', i + 1)
              if chars[close_bracket + 1]? == '(' &&
                 (close_paren = find_char(chars, ')', close_bracket + 2))
                link_text = chars[i + 1...close_bracket].join
                link_style = @stylesheet[Element::Link]
                out << link_style.to_ansi
                out << render_inline(link_text, link_style)
                out << replay_sequence(block_style, inline_stack)
                i = close_paren + 1
              else
                out << '['
                i += 1
              end
            else
              out << '['
              i += 1
            end
            # -- "**": bold (must be checked before single "*") ----------------
          elsif c == '*' && i + 1 < n && chars[i + 1] == '*'
            if inline_stack.any? { |entry| entry[0] == Element::Bold }
              pop_inline(Element::Bold, inline_stack)
              out << replay_sequence(block_style, inline_stack)
            else
              if find_two_chars(chars, '*', i + 2)
                seq = @stylesheet[Element::Bold].to_ansi
                inline_stack << {Element::Bold, seq}
                out << seq
              else
                out << "**"
              end
            end
            i += 2
            # -- "~~": strikethrough -------------------------------------------
          elsif c == '~' && i + 1 < n && chars[i + 1] == '~'
            if inline_stack.any? { |entry| entry[0] == Element::Strikethrough }
              pop_inline(Element::Strikethrough, inline_stack)
              out << replay_sequence(block_style, inline_stack)
            else
              if find_two_chars(chars, '~', i + 2)
                seq = @stylesheet[Element::Strikethrough].to_ansi
                inline_stack << {Element::Strikethrough, seq}
                out << seq
              else
                out << "~~"
              end
            end
            i += 2
            # -- "*": italic ---------------------------------------------------
          elsif c == '*'
            if inline_stack.any? { |entry| entry[0] == Element::Italic }
              pop_inline(Element::Italic, inline_stack)
              out << replay_sequence(block_style, inline_stack)
            else
              if find_single_star(chars, i + 1)
                seq = @stylesheet[Element::Italic].to_ansi
                inline_stack << {Element::Italic, seq}
                out << seq
              else
                out << '*'
              end
            end
            i += 1
            # -- "_": italic, mid-word exemption -------------------------------
          elsif c == '_'
            prev_word = i > 0 && chars[i - 1].alphanumeric?
            next_word = i + 1 < n && chars[i + 1].alphanumeric?
            if prev_word && next_word
              out << '_'
            elsif inline_stack.any? { |entry| entry[0] == Element::Italic }
              pop_inline(Element::Italic, inline_stack)
              out << replay_sequence(block_style, inline_stack)
            else
              if find_closing_underscore(chars, i + 1)
                seq = @stylesheet[Element::Italic].to_ansi
                inline_stack << {Element::Italic, seq}
                out << seq
              else
                out << '_'
              end
            end
            i += 1
          else
            out << c
            i += 1
          end
        end
        out << replay_sequence(block_style, inline_stack) unless inline_stack.empty?
        out.to_s
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
