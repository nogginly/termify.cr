module Termify::ANSI
  class SubScroller
    getter term : Terminal
    getter lines : Int32

    private getter top_row : Int32

    def initialize(@term, height : Int32)
      @lines = height.clamp(3, 10)
      @top_row = -1
    end

    # Return true if sub-scroller is active (i.e. started, not yet stopped)
    def active?
      top_row.positive?
    end

    # Setup the sub-scroll region and place the cursor at top row within it.
    # All subsequent output will scroll within the region.
    def start
      # Reserve lines below current position
      print "\n" * lines
      print "\e[#{lines}A" # move back up
      STDOUT.flush

      # Constrain scroll region
      top = @top_row = term.cursor_row
      bot = top + lines - 1
      print "\e[#{top};#{bot}r"
      # Move to top of scroll region
      print "\e[#{top};1H"
      STDOUT.flush
    end

    def self.write_thinking_chunk(text : String)
      print text
      STDOUT.flush
    end

    # Stop using the sub-scroll region, undo the scroll constraint, and
    # place the cursor at the top or after the bottom of the region
    # based on `top` parameter which defaults to `false` for bottom.
    def stop(top = false)
      # Restore full-screen scrolling
      print "\e[r"
      # Move cursor to line just after the region
      row = top ? top_row : top_row + lines
      print "\e[#{row};1H"
      STDOUT.flush
      # Deactivate
      @top_row = -1
    end
  end
end
