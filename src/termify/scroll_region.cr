require "./ansi"
require "./terminal"

module Termify
  # Confines output to a fixed-height region of the terminal, so that streaming
  # text scrolls within it while the rest of the screen stays put.
  class ScrollRegion
    getter term : Terminal
    getter lines : Int32

    private getter top_row : Int32

    # Height is clamped to the useful range; below three the region cannot show
    # movement, and above ten it stops reading as a subordinate area.
    def initialize(@term, height : Int32)
      @lines = height.clamp(3, 10)
      @top_row = -1
    end

    # Return true if the region is active (i.e. started, not yet stopped)
    def active?
      top_row.positive?
    end

    # Setup the scroll region and place the cursor at top row within it.
    # All subsequent output will scroll within the region.
    def start
      io = term.output

      # Reserve the region's lines below the cursor, then return to where it was
      io << "\n" * lines
      io << ANSI::Cursor.up(lines)
      io.flush

      # Ask where that left us, and confine scrolling from there
      top = @top_row = term.cursor_row
      io << ANSI::Screen.scroll_region(top, top + lines - 1)
      io << ANSI::Cursor.to(1, top)
      io.flush
    end

    # Stop using the scroll region, undo the scroll constraint, and
    # place the cursor at the top or after the bottom of the region
    # based on `top` parameter which defaults to `false` for bottom.
    def stop(top = false)
      io = term.output
      io << ANSI::Screen.reset_scroll_region
      io << ANSI::Cursor.to(1, top ? top_row : top_row + lines)
      io.flush
      @top_row = -1
    end
  end
end
