module Termify
  module Markdown
    # Write-only IO wrapper that prepends a prefix string at the start of each
    # line and appends a suffix string just before each newline.
    # Used by Renderer to inject blockquote styling (e.g. prefix "│ " and
    # suffix "\e[K\e[0m" when a bg is set) transparently, so nested renderers
    # (lists, code, tables) need no blockquote awareness.
    #
    # @at_line_start tracks whether the next character begins a new line.
    # Every line, including blank lines, receives both prefix and suffix.
    class BlockquoteIO < IO
      def initialize(@io : IO, @prefix : String, @suffix : String = "")
        @at_line_start = true
      end

      def write(slice : Bytes) : Nil
        String.new(slice).each_char do |char|
          if @at_line_start
            @io << @prefix
            @at_line_start = false
          end
          if char == '\n'
            @io << @suffix unless @suffix.empty?
            @at_line_start = true
          end
          @io << char
        end
      end

      # BlockquoteIO is write-only.
      def read(slice : Bytes) : Int32
        raise IO::Error.new("BlockquoteIO is write-only")
      end
    end
  end
end
