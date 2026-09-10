require "../src/termify"

file_to_read = ARGV[0]? || abort("USAGE: scrollcat FILENAME [ height ]\nrRequires file name to read.")
height = (ARGV[1]?.try(&.to_i?) || 5).clamp(3, 10)

term = Termify.terminal
term.setup_console
at_exit { term.restore_console }

region = Termify::ScrollRegion.new(term, height)
puts "┌─────── Scroll region (#{height} lines) ───────────────"
region.start
File.each_line(file_to_read, chomp: false) do |line|
  line.split(' ').each do |phrase|
    print phrase, ' '
    STDOUT.flush
    sleep(10.milliseconds)
  end
end
region.stop
puts "└─────────────────────────────────────────"
puts
