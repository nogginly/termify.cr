require "../src/termify"

Termify.render_markdown do |io|
  io.puts "# Hello"
  io << "_Hello_, **World!**"
end
