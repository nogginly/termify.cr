module Termify
  module TerminalCommon
    # Setup console terminal mode; does nothing on *nix platforms
    # but is needed for Windows
    def setup_console; end

    # Restore console (after setup); does nothing on *nix platforms
    # but is needed for Windows
    def restore_console; end

    # Temporarily switch input to raw + VT mode, yield, then restore input mode.
    # Output mode is left as-is (already set up by setup_console).
    abstract def with_raw_input(&)

    # Return the row number of the cursor's current position
    def cursor_row : Int32
      with_raw_input do
        print "\e[6n"
        STDOUT.flush
        response = String.build do |str_io|
          loop do
            break if (ch = STDIN.read_char) == 'R'
            str_io << ch
          end
        end
        response.match(/\[(\d+);/).try(&.[1].to_i) || 1
      end
    end

    # Returns true if the terminal is likely to support ANSI color output.
    # Does not change the console; use `#setup_console` for that.
    def color_supported? : Bool
      return false if ENV.has_key?("NO_COLOR")
      return false if ENV["TERM"]? == "dumb"
      return true if ENV.has_key?("COLORTERM")

      # Linux / macOS / BSD — ANSI is safe by default
      true
    end

    # Returns true if the terminal advertises truecolor support.
    # Callers should fall back to 256-color or 8/16 if this returns false.
    def truecolor_supported? : Bool
      return false unless color_supported?
      ENV["COLORTERM"]?.try { |value| value == "truecolor" || value == "24bit" } || false
    end

    # Private constructor
    protected def initialize; end
  end
end

# Select the platform-specific terminal at compile-time
{% if flag?(:linux) || flag?(:darwin) %}
  require "./terminal/unix.cr"
{% elsif flag?(:windows) %}
  require "./terminal/windows.cr"
{% else %}
  # Raise compile-time error to indicate no Terminal supported on the platform
  raise "Terminal unsupported; requires Linux, macOS, or Windows."
{% end %}
