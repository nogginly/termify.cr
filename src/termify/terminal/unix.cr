require "lib_c"

module Termify
  class UnixTerminal
    include TerminalCommon

    {% if flag?(:linux) %}
      VMIN  = 6
      VTIME = 5
    {% elsif flag?(:darwin) %}
      VMIN  = 16
      VTIME = 17
    {% end %}

    # Temporarily switch input to raw + VT mode, yield, then restore input mode.
    # Output mode is left as-is (already set up by setup_console).
    def with_raw_input(&)
      # Save current terminal settings
      LibC.tcgetattr(STDIN.fd, out old_termios)
      raw = old_termios

      # Disable canonical mode and echo
      raw.c_lflag &= ~(LibC::ICANON | LibC::ECHO)
      raw.c_cc[VMIN] = 1  # read at least 1 char
      raw.c_cc[VTIME] = 0 # no timeout

      LibC.tcsetattr(STDIN.fd, LibC::TCSANOW, pointerof(raw))

      begin
        yield
      ensure
        # Always restore, even on exception
        LibC.tcsetattr(STDIN.fd, LibC::TCSANOW, pointerof(old_termios))
      end
    end
  end

  alias Terminal = UnixTerminal
end
