require "../src/termify"

file_to_read = ARGV[0]? || abort("USAGE: scrollcat FILENAME [ height ]\nrRequires file name to read.")
height = (ARGV[1]?.try(&.to_i?) || 5).clamp(3, 10)

term = Termify.terminal
term.setup_console
at_exit { term.restore_console }

subscroll = Termify::ANSI::SubScroller.new(term, height)
puts "┌─────── Sub-scroller (#{height} lines) ───────────────"
subscroll.start
File.each_line(file_to_read, chomp: false) do |line|
  line.split(' ').each do |phrase|
    print phrase, ' '
    STDOUT.flush
    sleep(10.milliseconds)
  end
end
subscroll.stop
puts "└─────────────────────────────────────────"
puts
