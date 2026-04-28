module Termify
  # Single source of truth for all ANSI escape sequences.
  # The renderer and stylesheet never hardcode sequences — they reference this module.
  module ANSI
    # -------------------------------------------------------------------------
    # SGR attributes
    # -------------------------------------------------------------------------

    RESET         = "\e[0m"
    BOLD          = "\e[1m"
    DIM           = "\e[2m"
    ITALIC        = "\e[3m"
    UNDERLINE     = "\e[4m"
    STRIKETHROUGH = "\e[9m"

    # -------------------------------------------------------------------------
    # Standard foreground colors (8/16)
    # -------------------------------------------------------------------------

    FG_BLACK   = "\e[30m"
    FG_RED     = "\e[31m"
    FG_GREEN   = "\e[32m"
    FG_YELLOW  = "\e[33m"
    FG_BLUE    = "\e[34m"
    FG_MAGENTA = "\e[35m"
    FG_CYAN    = "\e[36m"
    FG_WHITE   = "\e[37m"
    FG_DEFAULT = "\e[39m"

    # Bright variants (high-intensity)

    FG_BRIGHT_BLACK   = "\e[90m"
    FG_BRIGHT_RED     = "\e[91m"
    FG_BRIGHT_GREEN   = "\e[92m"
    FG_BRIGHT_YELLOW  = "\e[93m"
    FG_BRIGHT_BLUE    = "\e[94m"
    FG_BRIGHT_MAGENTA = "\e[95m"
    FG_BRIGHT_CYAN    = "\e[96m"
    FG_BRIGHT_WHITE   = "\e[97m"

    # -------------------------------------------------------------------------
    # Standard background colors (8/16)
    # -------------------------------------------------------------------------

    BG_BLACK   = "\e[40m"
    BG_RED     = "\e[41m"
    BG_GREEN   = "\e[42m"
    BG_YELLOW  = "\e[43m"
    BG_BLUE    = "\e[44m"
    BG_MAGENTA = "\e[45m"
    BG_CYAN    = "\e[46m"
    BG_WHITE   = "\e[47m"
    BG_DEFAULT = "\e[49m"

    BG_BRIGHT_BLACK   = "\e[100m"
    BG_BRIGHT_RED     = "\e[101m"
    BG_BRIGHT_GREEN   = "\e[102m"
    BG_BRIGHT_YELLOW  = "\e[103m"
    BG_BRIGHT_BLUE    = "\e[104m"
    BG_BRIGHT_MAGENTA = "\e[105m"
    BG_BRIGHT_CYAN    = "\e[106m"
    BG_BRIGHT_WHITE   = "\e[107m"

    # -------------------------------------------------------------------------
    # 256-color (xterm palette)
    # -------------------------------------------------------------------------

    # Returns a foreground 256-color sequence. *n* must be 0..255.
    def self.fg256(n : Int) : String
      "\e[38;5;#{n}m"
    end

    # Returns a background 256-color sequence. *n* must be 0..255.
    def self.bg256(n : Int) : String
      "\e[48;5;#{n}m"
    end

    # -------------------------------------------------------------------------
    # Truecolor (24-bit)
    # -------------------------------------------------------------------------

    # Returns a foreground truecolor sequence.
    def self.fg_truecolor(r : Int, g : Int, b : Int) : String
      "\e[38;2;#{r};#{g};#{b}m"
    end

    # Returns a background truecolor sequence.
    def self.bg_truecolor(r : Int, g : Int, b : Int) : String
      "\e[48;2;#{r};#{g};#{b}m"
    end

    # -------------------------------------------------------------------------
    # Composition
    # -------------------------------------------------------------------------

    # Concatenates multiple SGR codes into one string.
    # Callers may also just concatenate constants directly; this helper exists
    # for programmatic construction (e.g. stylesheet merges).
    def self.sequence(*codes : String) : String
      codes.join
    end

    # Emits a full reset followed by every sequence on *stack* (bottom → top).
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
