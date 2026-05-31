module Termify::ANSI
  module Cursor
    # Move the cursor up n lines. 0 is the same as 1.
    def self.up(n = 0) : String
      n <= 1 ? "\e[A" : "\e[#{n}A"
    end

    # Move the cursor down n lines. 0 is the same as 1.
    def self.down(n = 0) : String
      n <= 1 ? "\e[B" : "\e[#{n}B"
    end

    # Move the cursor right n columns. 0 is the same as 1.
    def self.right(n = 0) : String
      n <= 1 ? "\e[C" : "\e[#{n}C"
    end

    # Move the cursor left n columns. 0 is the same as 1.
    def self.left(n = 0) : String
      n <= 1 ? "\e[D" : "\e[#{n}D"
    end

    # Move the cursor to line y, column x. 0 is the same as 1.
    # This indexes from the top left corner of the screen.
    def self.to(x = 0, y = 0) : String
      (x <= 1 && y <= 1) ? "\e[H" : "\e[#{y};#{x}H"
    end

    def self.save : String
      "\e7"
    end

    def self.restore : String
      "\e8"
    end

    def self.hide : String
      "\e[?25l"
    end

    def self.show : String
      "\e[?25h"
    end
  end
end
