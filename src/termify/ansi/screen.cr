module Termify::ANSI
  module Screen
    def self.switch_to_alternate : String
      "\e[?1049h"
    end

    def self.switch_to_default : String
      "\e[?1049l"
    end

    # Confine scrolling to rows top..bottom inclusive, indexed from 1.
    # Output outside the region no longer scrolls the screen.
    def self.scroll_region(top : Int32, bottom : Int32) : String
      "\e[#{top};#{bottom}r"
    end

    # Restore scrolling to the whole screen.
    def self.reset_scroll_region : String
      "\e[r"
    end
  end
end
