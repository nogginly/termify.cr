require "./style_sheet"

module Termify
  module Markdown
    # Renders Markdown inline markup -- code spans, HTML tags, links, bold,
    # italic and strikethrough -- into ANSI-styled text.
    #
    # A single left-to-right pass over the characters. There is no tokenizer
    # and no tree; open spans live on `inline_stack` as {element, sequence}
    # pairs. Closing a span does not emit a terminating code, because ANSI has
    # no composable "un-bold": instead `replay_sequence` emits RESET, the block
    # style, and every sequence still open. The state is rebuilt from scratch
    # each time a span closes.
    #
    # Scanners are ordered by priority in `render`: code spans first (they do
    # not nest), then HTML, links, then the emphasis markers.
    class InlineRenderer
      private INLINE_HTML = /<\/?[a-zA-Z][^>]*>/

      def initialize(@stylesheet : Stylesheet)
      end

      # Renders *text* as ANSI-styled output, restoring *block_style* whenever
      # an inline span closes. Supported spans, in priority order:
      #
      #   `code`      -- CodeInline (greedy, no nesting inside)
      #   <tag>       -- HtmlTag (emitted verbatim)
      #   [text](url) -- Link (URL suppressed; text re-enters `render`)
      #   **text**    -- Bold
      #   ~~text~~    -- Strikethrough
      #   *text*      -- Italic
      #   _text_      -- Italic (mid-word underscores emitted as literals)
      def render(text : String, block_style : Style) : String
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
            buf << render(link_text, link_style)
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

      # -- styled runs -------------------------------------------------------

      # A stretch of text and the ANSI sequence active across it. `ansi` is the
      # full active sequence, not a delta, so a run can be emitted on its own.
      record Run, text : String, ansi : String do
        def styled : String
          ansi.empty? ? text : "#{ansi}#{text}#{ANSI::RESET}"
        end
      end

      # SGR sequences, used to split rendered output back into runs.
      private SGR_RE = /\e\[[0-9;]*m/

      # Renders *text* as a sequence of runs: plain text paired with the ANSI
      # active across it. Escapes never appear in `Run#text`, so callers can
      # measure width, wrap, or lay out on the text and re-apply styling
      # afterwards -- which is what table cells need, since tablo sizes columns
      # on what it is given.
      #
      # Derived from `#render` rather than scanned separately, so the two can
      # never disagree about what the markup means.
      def runs(text : String, block_style : Style) : Array(Run)
        rendered = render(text, block_style)
        runs = [] of Run
        # `render` does not emit the block style itself -- callers write it
        # before calling in, and `replay_sequence` re-emits it only after a
        # span closes. Seed it here so every run is standalone.
        active = block_style.to_ansi
        pos = 0

        rendered.scan(SGR_RE) do |match|
          seq = match[0]
          chunk = rendered[pos...match.begin(0)]
          runs << Run.new(chunk, active) unless chunk.empty?
          # RESET clears the active sequence; anything else layers onto it,
          # mirroring how `replay_sequence` rebuilds state at a span boundary.
          active = seq == ANSI::RESET ? "" : active + seq
          pos = match.begin(0) + seq.size
        end

        tail = rendered[pos..]
        runs << Run.new(tail, active) unless tail.empty?
        runs
      end

      # The visible text of *text* with all markup consumed and no escapes.
      # Equivalent to joining `#runs`, but stated separately because callers
      # laying out a table want the plain string on its own.
      def plain(text : String, block_style : Style) : String
        runs(text, block_style).map(&.text).join
      end
    end
  end
end
