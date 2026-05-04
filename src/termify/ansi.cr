require "colorize"

require "./ansi/*"

module Termify
  # Single source of truth for all ANSI escape sequences.
  # The renderer and stylesheet never hardcode sequences — they reference this module.
  #
  # Colors are expressed as ANSI::Color values (ColorANSI, Color256, ColorRGB).
  # Use ANSI.fg / ANSI.bg to convert them to escape sequences.
  module ANSI
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
    # Terminal detection
    # -------------------------------------------------------------------------

    # Returns true if the terminal is likely to support ANSI color output.
    #
    # Rules (in priority order):
    #   1. NO_COLOR set (any value) → false  (no-color.org)
    #   2. TERM=dumb                → false
    #   3. COLORTERM set            → true   (explicit opt-in)
    #   4. Platform check           → true on POSIX; Windows path below
    #   5. Fallback                 → false
    def self.color_supported? : Bool
      return false if ENV.has_key?("NO_COLOR")
      return false if ENV["TERM"]? == "dumb"
      return true if ENV.has_key?("COLORTERM")

      {% if flag?(:win32) %}
        windows_color_supported?
      {% else %}
        # Linux / macOS / BSD — ANSI is safe by default
        true
      {% end %}
    end

    # Returns true if the terminal advertises truecolor support.
    # Callers should fall back to 256-color or 8/16 if this returns false.
    def self.truecolor_supported? : Bool
      color_supported? && ENV["COLORTERM"]?.try { |v| v == "truecolor" || v == "24bit" } || false
    end

    # -------------------------------------------------------------------------
    # Windows VT processing (compile-guarded — elided on POSIX)
    # -------------------------------------------------------------------------
    {% if flag?(:win32) %}
      @[Link("kernel32")]
      lib LibKernel32
        alias HANDLE = Void*
        alias DWORD = UInt32

        STD_OUTPUT_HANDLE                  =    -11_i32
        ENABLE_VIRTUAL_TERMINAL_PROCESSING = 0x0004_u32

        fun GetStdHandle(nStdHandle : DWORD) : HANDLE
        fun GetConsoleMode(hConsoleHandle : HANDLE, lpMode : UInt32*) : Int32
        fun SetConsoleMode(hConsoleHandle : HANDLE, dwMode : UInt32) : Int32
      end

      # Attempts to enable VT processing on Windows ConHost (Win10 1511+).
      # No-op if already enabled or if running under Windows Terminal.
      # Should be called once at program startup on Windows.
      def self.enable_vt_processing : Nil
        return if ENV.has_key?("WT_SESSION")

        handle = LibKernel32.GetStdHandle(LibKernel32::STD_OUTPUT_HANDLE)
        return if handle.null?

        mode = 0_u32
        return unless LibKernel32.GetConsoleMode(handle, pointerof(mode)) != 0

        unless (mode & LibKernel32::ENABLE_VIRTUAL_TERMINAL_PROCESSING) != 0
          LibKernel32.SetConsoleMode(
            handle,
            mode | LibKernel32::ENABLE_VIRTUAL_TERMINAL_PROCESSING
          )
        end
      end

      private def self.windows_color_supported? : Bool
        # Windows Terminal sets WT_SESSION
        return true if ENV.has_key?("WT_SESSION")

        # Try ConHost VT — probe by attempting SetConsoleMode
        handle = LibKernel32.GetStdHandle(LibKernel32::STD_OUTPUT_HANDLE)
        return false if handle.null?

        mode = 0_u32
        return false unless LibKernel32.GetConsoleMode(handle, pointerof(mode)) != 0

        result = LibKernel32.SetConsoleMode(
          handle,
          mode | LibKernel32::ENABLE_VIRTUAL_TERMINAL_PROCESSING
        )
        result != 0
      end
    {% else %}
      # No-op on POSIX — VT processing is always available.
      def self.enable_vt_processing : Nil
      end
    {% end %}
  end
end
