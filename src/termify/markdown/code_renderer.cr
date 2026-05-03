require "./style_sheet"
require "./style/code_block_style"
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
    # Line numbering is enabled when style.line_number_format is non-nil;
    # the format string is passed to sprintf with the current line number.
    class CodeRenderer
      getter language : String

      def initialize(
        @language : String,
        @style : CodeBlockStyle,
        @io : IO,
        @indent : String,
      )
        @line_number = 0
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
        @io << ansi << @indent << gutter << prefix << line << reset << '\n'
      end

      # Called when the closing fence marker is detected.
      # Placeholder for future use (highlighter flush).
      def close : Nil
      end
    end
  end
end
