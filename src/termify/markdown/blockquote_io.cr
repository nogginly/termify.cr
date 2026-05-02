module Termify
  module Markdown
    # Write-only IO wrapper that prepends a prefix string at the start of each
    # non-blank line. Used by Renderer to inject blockquote styling (e.g. "| ")
    # transparently, so nested renderers (lists, code, tables) need no
    # blockquote awareness.
    #
    # @at_line_start tracks whether the next character begins a new line.
    # Every line, including blank lines, receives the prefix.
    class BlockquoteIO < IO
      def initialize(@io : IO, @prefix : String)
        @at_line_start = true
      end

      def write(slice : Bytes) : Nil
        String.new(slice).each_char do |char|
          if @at_line_start
            @io << @prefix
            @at_line_start = false
          end
          @io << char
          @at_line_start = (char == '\n')
        end
      end

      # BlockquoteIO is write-only.
      def read(slice : Bytes) : Int32
        raise IO::Error.new("BlockquoteIO is write-only")
      end
    end
  end
end
