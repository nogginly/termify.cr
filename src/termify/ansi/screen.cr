module Termify::ANSI
  module Screen
    def self.switch_to_alt_screen : String
      "\e[?1049h"
    end

    def self.switch_to_normal_screen : String
      "\e[?1049l"
    end
  end
end
