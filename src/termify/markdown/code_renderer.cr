require "./style_sheet"
require "./style/code_block_style"
require "../ansi"
require "tartrazine"

# -- Monkeypatch: resumable per-line formatting -----------------------------
# Adds format_line to Tartrazine::Ansi so CodeRenderer can feed one line at
# a time while carrying lexer state across calls.
# The key insight: Tokenizer holds all mutable state in @state_stack and @pos;
# copying state_stack from the previous tokenizer (with .dup to avoid aliasing)
# lets the new tokenizer resume mid-construct (e.g. inside a block comment).
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

module Termify
  module Markdown
    # Streaming renderer for code fence bodies.
    #
    # Instantiated by Renderer when a fence opens; each body line is passed to
    # #feed as it arrives. #close is called when the closing fence marker is
    # detected. Neither method buffers -- output is emitted immediately.
    #
    # @language is stored for future use (syntax highlighting).
    # @indent is the list visual indent active at fence-open time.
    # Line numbering is enabled when style.line_number_format is non-nil;
    # the format string is passed to sprintf with the current line number.
    # Syntax highlighting is enabled when style.highlight_theme is non-nil
    # and @language is non-empty. Falls back to plain output gracefully if
    # the language or theme is unknown.
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
        @prev_tokenizer = nil.as(Tartrazine::Tokenizer?)
        setup_highlighter
      end

      # Emits one code body line with block style applied. No inline parsing.
      # Prepends the formatted line number gutter when line_number_format is set.
      # gutter_style, when set, is applied to the gutter only; the block style
      # resumes for the code content.
      def feed(line : String) : Nil
        @line_number += 1
        ansi = @style.to_ansi
        prefix = @style.line_prefix || ""
        reset = ansi.empty? ? "" : ANSI::RESET
        gutter = if fmt = @style.line_number_format
                   text = sprintf(fmt, @line_number)
                   if gs = @style.gutter_style
                     gs_ansi = gs.to_ansi
                     gs_ansi.empty? ? text : "#{gs_ansi}#{text}#{ANSI::RESET}#{ansi}"
                   else
                     text
                   end
                 else
                   ""
                 end
        if (fmt = @formatter) && (lex = @hl_lexer)
          # Highlighted path -- tartrazine applies token colours.
          # Block bg is intentionally not re-applied between tokens since
          # tartrazine's colorize omits background; it would be cleared by
          # each token's reset anyway.
          buf = IO::Memory.new
          @prev_tokenizer = fmt.format_line(line, lex, buf, @prev_tokenizer)
          @io << @indent << gutter << prefix << buf.to_s << '\n'
        else
          @io << ansi << @indent << gutter << prefix << line << reset << '\n'
        end
      end

      # Called when the closing fence marker is detected.
      # Resets highlighter state so the renderer is safe to reuse.
      def close : Nil
        @prev_tokenizer = nil
      end

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
