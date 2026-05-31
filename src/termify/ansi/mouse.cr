module Termify::ANSI
  module Mouse
    # --- Mouse Control ---
    def self.enable : String
      "\e[?1000h\e[?1002h\e[?1003h\e[?1015h\e[?1006h"
    end

    def self.disable : String
      "\e[?1000l\e[?1002l\e[?1003l\e[?1015l\e[?1006l"
    end
  end
end
