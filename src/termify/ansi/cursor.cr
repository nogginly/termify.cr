module Termify::ANSI
  module Cursor
    # Move the cursor up n lines. 0 is the same as 1.
    def self.cursor_up(n = 0) : String
      n <= 1 ? "\e[A" : "\e[#{n}A"
    end

    # Move the cursor down n lines. 0 is the same as 1.
    def self.cursor_down(n = 0) : String
      n <= 1 ? "\e[B" : "\e[#{n}B"
    end

    # Move the cursor right n columns. 0 is the same as 1.
    def self.cursor_right(n = 0) : String
      n <= 1 ? "\e[C" : "\e[#{n}C"
    end

    # Move the cursor left n columns. 0 is the same as 1.
    def self.cursor_left(n = 0) : String
      n <= 1 ? "\e[D" : "\e[#{n}D"
    end

    # Move the cursor to line y, column x. 0 is the same as 1.
    # This indexes from the top left corner of the screen.
    def self.cursor_to(x = 0, y = 0) : String
      (x <= 1 && y <= 1) ? "\e[H" : "\e[#{y};#{x}H"
    end

    def self.cursor_save : String
      "\e7"
    end

    def self.cursor_restore : String
      "\e8"
    end

    def self.cursor_hide : String
      "\e[?25l"
    end

    def self.cursor_show : String
      "\e[?25h"
    end
  end
end
