lib WinCon
  # Handle retrieval
  fun GetStdHandle(nStdHandle : UInt32) : Void*

  # Console mode (VT processing, raw input)
  fun GetConsoleMode(hConsoleHandle : Void*, lpMode : UInt32*) : Int32
  fun SetConsoleMode(hConsoleHandle : Void*, dwMode : UInt32) : Int32

  # Flush input queue (so \e[6n response isn't mixed with queued input)
  fun FlushConsoleInputBuffer(hConsoleInput : Void*) : Int32
end

module Termify
  class WindowsTerminal
    include TerminalCommon

    # Standard handle IDs
    private STD_INPUT_HANDLE  = 0xFFFFFFF6_u32
    private STD_OUTPUT_HANDLE = 0xFFFFFFF5_u32

    # Console mode flags
    private ENABLE_VIRTUAL_TERMINAL_PROCESSING = 0x0004_u32 # output: enable ANSI escapes
    private ENABLE_PROCESSED_OUTPUT            = 0x0001_u32 # output: required companion flag
    private ENABLE_LINE_INPUT                  = 0x0002_u32 # input: line-buffered (canonical)
    private ENABLE_ECHO_INPUT                  = 0x0004_u32 # input: echo keystrokes
    private ENABLE_VIRTUAL_TERMINAL_INPUT      = 0x0200_u32 # input: receive VT sequences (e.g. \e[6n response)

    @stdin_handle = WinCon.GetStdHandle(STD_INPUT_HANDLE)
    @stdout_handle = WinCon.GetStdHandle(STD_OUTPUT_HANDLE)

    # Save original console modes so we can restore them
    @orig_out_mode : UInt32 = 0_u32
    @orig_in_mode : UInt32 = 0_u32

    def setup_console
      WinCon.GetConsoleMode(@stdout_handle, pointerof(@orig_out_mode))
      WinCon.GetConsoleMode(@stdin_handle, pointerof(@orig_in_mode))

      # Enable ANSI escape processing on output
      WinCon.SetConsoleMode(
        @stdout_handle,
        ENABLE_PROCESSED_OUTPUT | ENABLE_VIRTUAL_TERMINAL_PROCESSING
      )
    end

    def restore_console
      WinCon.SetConsoleMode(@stdout_handle, @orig_out_mode)
      WinCon.SetConsoleMode(@stdin_handle, @orig_in_mode)
    end

    # Temporarily switch input to raw + VT mode, yield, then restore input mode.
    # Output mode is left as-is (already set up by setup_console).
    def with_raw_input(&)
      raw_in = ENABLE_VIRTUAL_TERMINAL_INPUT # no line buffering, no echo, VT responses pass through
      WinCon.SetConsoleMode(@stdin_handle, raw_in)
      WinCon.FlushConsoleInputBuffer(@stdin_handle)
      begin
        yield
      ensure
        WinCon.SetConsoleMode(@stdin_handle, @orig_in_mode)
      end
    end

    def self.color_supported? : Bool
      # Windows Terminal sets WT_SESSION
      ENV.has_key?("WT_SESSION") || super
    end
  end

  alias Terminal = WindowsTerminal
end
