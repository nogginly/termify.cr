require "./style_sheet"
require "./style/code_block_style"
require "../ansi"
require "tartrazine"

# -- Monkeypatch: resumable per-line formatting -----------------------------
# Adds format_line to Tartrazine::Ansi for the streaming highlight path.
# Enabled only when compiled with -Dstreaming_highlight.
#
# NOTE: This approach works for lexers that use push/pop state machines for
# multi-line constructs, but NOT for lexers like JavaScript that use a single
# dot_all regex spanning multiple lines. The default buffering path is correct
# for all lexers; this path exists for experimentation only.
{% if flag?(:streaming_highlight) %}
  module Tartrazine
    class Ansi
      # Format a single line, resuming state from prev_tokenizer when provided.
      # Appends colorized content (without the trailing newline) to outp.
      # Returns the tokenizer so the caller can pass it back on the next call.
      #
      # Passes secondary: true to Tokenizer to suppress the ensure_nl \n
      # injection. ensure_nl adds \n which, if unmatched in the current lexer
      # state (e.g. inside a /* block comment */), triggers the fallback:
      # state_stack = ["root"] -- destroying multi-line construct context.
      # With secondary: true that branch is skipped entirely.
      def format_line(line : String, lexer : BaseLexer, outp : IO,
                      prev_tokenizer : Tokenizer? = nil) : Tokenizer
        tokenizer = Tokenizer.new(lexer, line, true)
        tokenizer.state_stack = prev_tokenizer.state_stack.dup if prev_tokenizer
        tokenizer.each do |token|
          # Guard against any stray \n tokens just in case.
          next if token[:value] == "\n"
          outp << colorize(token[:value], token[:type])
        end
        tokenizer
      end
    end
  end
{% end %}

module Termify
  module Markdown
    # Streaming renderer for code fence bodies.
    #
    # Instantiated by Renderer when a fence opens; each body line is passed to
    # #feed as it arrives. #close is called when the closing fence marker is
    # detected.
    #
    # Highlighting behaviour:
    # - Default (buffering): lines are accumulated in feed; close renders the
    #   full buffer via tartrazine and emits highlighted lines. Correct for all
    #   lexers, including those that use dot_all multi-line regexes (e.g. JS).
    # - Streaming (-Dstreaming_highlight): feed emits immediately using
    #   format_line with state_stack carry-over. Works for push/pop state
    #   machine lexers; fails for dot_all single-pass lexers like JavaScript.
    #
    # When no highlight_theme is set or language is empty, both paths emit
    # plain styled output immediately without buffering.
    class CodeRenderer
      getter language : String

      def initialize(
        @language : String,
        @style : CodeBlockStyle,
        @io : IO,
        @indent : String,
      )
        @line_number = 0
        @formatter = nil.as(Tartrazine::Ansi?)
        @hl_lexer = nil.as(Tartrazine::BaseLexer?)
        @lines = [] of String
        {% if flag?(:streaming_highlight) %}
          @prev_tokenizer = nil.as(Tartrazine::Tokenizer?)
        {% end %}
        setup_highlighter
      end

      # Accumulates a line for highlighted rendering (flushed in close),
      # or emits immediately when highlighting is not active.
      def feed(line : String) : Nil
        if @formatter && @hl_lexer
          {% if flag?(:streaming_highlight) %}
            @line_number += 1
            emit_highlighted_line_streaming(line, @line_number)
          {% else %}
            @lines << line
          {% end %}
        else
          @line_number += 1
          emit_plain_line(line, @line_number)
        end
      end

      # Flushes buffered lines through tartrazine (buffering path),
      # or resets streaming state (streaming path).
      def close : Nil
        {% if flag?(:streaming_highlight) %}
          @prev_tokenizer = nil
        {% else %}
          if (fmt = @formatter) && (lex = @hl_lexer)
            emit_highlighted_buffer(fmt, lex)
          end
          @lines.clear
        {% end %}
      end

      private def emit_plain_line(line : String, number : Int32) : Nil
        ansi = @style.to_ansi
        prefix = @style.line_prefix || ""
        erase = (@style.bg && !ansi.empty?) ? ANSI::ERASE_LINE : ""
        reset = ansi.empty? ? "" : ANSI::RESET
        @io << ansi << @indent << gutter_for(number, ansi) << prefix << line << erase << reset << '\n'
      end

      private def gutter_for(number : Int32, ansi : String) : String
        fmt = @style.line_number_format
        return "" unless fmt
        text = sprintf(fmt, number)
        if gs = @style.gutter_style
          gs_ansi = gs.to_ansi
          gs_ansi.empty? ? text : "#{gs_ansi}#{text}#{ANSI::RESET}#{ansi}"
        else
          text
        end
      end

      private def emit_highlighted_buffer(fmt : Tartrazine::Ansi,
                                          lex : Tartrazine::BaseLexer) : Nil
        return if @lines.empty?
        buf = IO::Memory.new
        fmt.format(@lines.join('\n'), lex, buf)
        prefix = @style.line_prefix || ""
        buf.to_s.split('\n').each_with_index do |hl_line, idx|
          number = idx + 1
          @io << @indent << gutter_for(number, "") << prefix << hl_line << '\n'
        end
      end

      {% if flag?(:streaming_highlight) %}
        private def emit_highlighted_line_streaming(line : String, number : Int32) : Nil
          fmt = @formatter
          lex = @hl_lexer
          return unless fmt && lex
          buf = IO::Memory.new
          @prev_tokenizer = fmt.format_line(line, lex, buf, @prev_tokenizer)
          prefix = @style.line_prefix || ""
          @io << @indent << gutter_for(number, "") << prefix << buf.to_s << '\n'
        end
      {% end %}

      private def setup_highlighter : Nil
        theme = @style.highlight_theme
        return if theme.nil? || @language.empty?
        @formatter = Tartrazine::Ansi.new(theme: Tartrazine.theme(theme))
        @hl_lexer = Tartrazine.lexer(name: @language)
      rescue
        # Unknown language or theme -- fall back to plain output silently.
        @formatter = nil
        @hl_lexer = nil
      end
    end
  end
end
