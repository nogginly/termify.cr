require "../src/termify"

USAGE = "Usage: md2term <MARKDOWNFILE>\nRead a Markdown file (slowly) and render to terminal."
md_file = ARGV[0]? || abort(USAGE)

ss = Termify.markdown_stylesheet({
  "h1"         => {bold: true, line_prefix: "# ".colorize(:dark_gray).to_s, newline_after: true},
  "h2"         => {bold: true, line_prefix: "## ".colorize(:dark_gray).to_s, newline_after: true, newline_before: true},
  "h3"         => {bold: true, line_prefix: "### ".colorize(:dark_gray).to_s, newline_after: true, newline_before: true},
  "h4"         => {bold: true, fg: "white", line_prefix: "#### ".colorize(:dark_gray).to_s},
  "h5"         => {bold: true},
  "h6"         => {bold: true},
  "code_block" => {
    fg: :light_cyan, line_number_format: "%3d: ",
    highlight_theme: "catppuccin-macchiato",
    gutter_style: {dim: true},
  },
  "code_inline" => {fg: :red},
  "html_tag"    => {dim: true},
  "block_html"  => {dim: true},
  "list_item"   => {newline_after: true, newline_before: true},
  "block_quote" => {line_prefix: "│ ", newline_after: true, newline_before: true, bg: "Grey7"},
})

class Progress
  TICK = 100.milliseconds

  FRAMES = %w[\\ | / -]

  property label : String
  property lines : Int32

  def initialize(@label : String, @lines = 0, @io : IO = STDERR)
    @stop = Channel(Nil).new
    @drained = Channel(Nil).new
    @running = false
    @width = 0
  end

  def start : Nil
    return if @running || !@io.tty?

    @running = true
    started = Time.instant

    spawn do
      frame = 0
      loop do
        select # select runs all conditions and exits on first to return
        when @stop.receive?
          break
        when timeout(TICK)
          draw(FRAMES[frame % FRAMES.size], Time.instant - started)
          frame += 1
        end
      end
      erase
      @drained.send(nil)
    end
  end

  def stop : Nil
    return unless @running

    @running = false
    @stop.send(nil)
    @drained.receive?
  end

  private def draw(frame : String, elapsed : Time::Span) : Nil
    line = "#{frame} #{@label}#{" (#{lines} lines)" if lines.positive?}… #{elapsed.total_seconds.to_i}s"
    @io.print("\r#{line}")
    @io.flush
    @width = line.size
  end

  private def erase : Nil
    return if @width.zero?
    @io.print("\r#{" " * @width}\r")
    @io.flush
    @width = 0
  end
end

progress = Progress.new("")

# Intake lines faster until we're in progress events, then slow down a little.
SLOW = 150.milliseconds
FAST = 50.milliseconds
line_delay = FAST

handler = ->(event : Termify::Markdown::GatherEvent) {
  # puts "<#{event.phase}>"
  case event.phase
  when .started?
    progress.label = case event.kind
                     in .table?      then "gathering table"
                     in .code_block? then "gathering code"
                     end
    line_delay = SLOW
    progress.start
  when .finished?
    progress.stop
    line_delay = FAST
  when .progressed?
    progress.lines = event.units
  end
}

File.open(md_file, "r") do |file|
  Termify.render_markdown(STDOUT, ss, on_gather: handler) do |md_io|
    file.each_line do |line|
      md_io.puts(line)
      sleep line_delay
    end
  end
end
