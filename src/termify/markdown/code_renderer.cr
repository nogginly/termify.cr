require "./style_sheet"
require "../ansi"

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
    class CodeRenderer
      getter language : String

      def initialize(
        @language : String,
        @style : BlockStyle,
        @io : IO,
        @indent : String,
      )
      end

      # Emits one code body line with block style applied. No inline parsing.
      def feed(line : String) : Nil
        ansi = @style.to_ansi
        prefix = @style.line_prefix || ""
        reset = ansi.empty? ? "" : ANSI::RESET
        @io << ansi << @indent << prefix << line << reset << '\n'
      end

      # Called when the closing fence marker is detected.
      # Placeholder for future use (line number finalisation, highlighter flush).
      def close : Nil
      end
    end
  end
end
