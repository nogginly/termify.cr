module Termify::ANSI
  enum Erase
    Before # Erase up to (before) the cursor position
    After  # Erase from (after) the cursor position
    All    # Erase all regardless of cursor position
  end

  module Clear
    # Clear the screen and move the cursor to the top left corner.
    def self.clear_screen(how_much = Erase::All) : String
      case how_much
      when Erase::Before then "\e[1J"
      when Erase::After  then "\e[0J"
      when Erase::All    then "\e[H\e[2J"
      end
    end

    # Erases some or all of the line the cursor is on.
    def self.clear_line(how_much = Erase::All) : String
      case how_much
      when Erase::Before then "\e[1K"
      when Erase::After  then "\e[0K"
      when Erase::All    then "\e[2K"
      end
    end
  end
end
