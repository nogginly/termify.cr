module Termify::ANSI
  module Screen
    def self.switch_to_alternate : String
      "\e[?1049h"
    end

    def self.switch_to_default : String
      "\e[?1049l"
    end
  end
end
