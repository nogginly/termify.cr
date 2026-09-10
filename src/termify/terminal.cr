module Termify
  class Terminal
    # Row reported when the terminal cannot be asked, or answers unintelligibly.
    DEFAULT_CURSOR_ROW = 1

    # Upper bound on characters read while awaiting a cursor position report.
    # A well-formed reply is "ESC [ <row> ; <col> R" -- far shorter than this.
    private READ_LIMIT = 32

    # The row field of a cursor position report.
    private CURSOR_REPORT = /\[(\d+);/

    # Where queries are written and replies are read. Everything built on
    # `Terminal` writes through `output` rather than reaching for `STDOUT`,
    # so a caller and its terminal cannot address different devices.
    getter input : IO
    getter output : IO

    # True when both ends are a terminal, and so when a query may be asked at
    # all. Overriding this is how a spec reaches the code beyond the gate.
    def interactive? : Bool
      input.tty? && output.tty?
    end

    # Return the row number of the cursor's current position.
    #
    # Asking requires a terminal on both ends: the query goes to the output and
    # the reply arrives on the input. Where either is redirected there is nobody
    # to answer, so this returns `DEFAULT_CURSOR_ROW` rather than waiting.
    def cursor_row : Int32
      return DEFAULT_CURSOR_ROW unless interactive?

      with_raw_input do
        output << "\e[6n"
        output.flush
        response = String.build do |str_io|
          READ_LIMIT.times do
            char = input.read_char
            break if char.nil? || char == 'R'
            str_io << char
          end
        end
        response.match(CURSOR_REPORT).try(&.[1].to_i?) || DEFAULT_CURSOR_ROW
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

    def initialize(@input : IO = STDIN, @output : IO = STDOUT)
    end
  end
end

# Select the platform-specific terminal at compile-time
{% if flag?(:linux) || flag?(:darwin) %}
  require "./terminal/unix.cr"
{% elsif flag?(:windows) %}
  require "./terminal/windows.cr"
{% else %}
  # Compile-time error: no Terminal implementation exists for this target.
  {% raise "Terminal unsupported; requires Linux, macOS, or Windows." %}
{% end %}
