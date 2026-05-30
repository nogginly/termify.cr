require "colorize"

require "./ansi/*"

module Termify
  # Single source of truth for all ANSI escape sequences.
  # The renderer and stylesheet never hardcode sequences — they reference this module.
  #
  # Colors are expressed as ANSI::Color values (ColorANSI, Color256, ColorRGB).
  # Use ANSI.fg / ANSI.bg to convert them to escape sequences.
  module ANSI
    include Cursor
    include Screen
    include Clear
    include Mouse

    alias Color = Colorize::Color | Color256

    # -------------------------------------------------------------------------
    # SGR attributes
    # -------------------------------------------------------------------------

    RESET         = "\e[0m"
    ERASE_LINE    = "\e[K"
    BOLD          = "\e[1m"
    DIM           = "\e[2m"
    ITALIC        = "\e[3m"
    UNDERLINE     = "\e[4m"
    STRIKETHROUGH = "\e[9m"

    # -------------------------------------------------------------------------
    # Color helpers -- convert ANSI::Color to ANSI escape sequences.
    # ColorANSI values are the fg codes directly; bg = fg + 10.
    # Color256 and ColorRGB use the extended-color escape format.
    # -------------------------------------------------------------------------

    def self.fg(color : ANSI::Color) : String
      case color
      when Colorize::ColorANSI          then "\e[#{color.value}m"
      when Colorize::Color256, Color256 then "\e[38;5;#{color.value}m"
      when Colorize::ColorRGB           then "\e[38;2;#{color.red};#{color.green};#{color.blue}m"
      else
        ""
      end
    end

    def self.bg(color : ANSI::Color) : String
      case color
      when Colorize::ColorANSI          then "\e[#{color.value + 10}m"
      when Colorize::Color256, Color256 then "\e[48;5;#{color.value}m"
      when Colorize::ColorRGB           then "\e[48;2;#{color.red};#{color.green};#{color.blue}m"
      else
        ""
      end
    end

    # -------------------------------------------------------------------------
    # Composition
    # -------------------------------------------------------------------------

    # Concatenates multiple SGR codes into one string.
    def self.sequence(*codes : String) : String
      codes.join
    end

    # Emits a full reset followed by every sequence on *stack* (bottom -> top).
    # Called by the renderer whenever a style is popped from the inline stack.
    def self.reset_and_replay(stack : Array(String)) : String
      return RESET if stack.empty?
      RESET + stack.join
    end

    # -------------------------------------------------------------------------
    # Writing
    # -------------------------------------------------------------------------

    # Repeat a character using ANSI 'n' repetitions
    def self.repeat(char : String, times : Int32) : String
      return "" if times <= 0
      return char if times == 1
      "#{char}\e[#{times - 1}b"
    end
  end
end
