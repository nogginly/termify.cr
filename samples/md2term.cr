require "../src/termify"

USAGE = "Usage: md2term <MARKDOWNFILE>\nRead a Markdown file and render to terminal."
md_file = ARGV[0]? || abort(USAGE)

ss = Termify::Markdown::Stylesheet.new({
  :h1          => {bold: true, prefix: "# "},
  :h2          => {bold: true},
  :h3          => {bold: true},
  :h4          => {bold: true},
  :h5          => {bold: true},
  :h6          => {bold: true},
  :code_block  => {fg: Termify::ANSI::FG_WHITE, dim: true, prefix: "` "},
  :code_inline => {fg: Termify::ANSI::FG_RED},
  :html_tag    => {dim: true},
  :block_html  => {dim: true},
  :table       => {fg: Termify::ANSI::FG_DEFAULT},
  :block_quote => {prefix: "│ "},
})

File.open(md_file, "r") do |file|
  Termify.render_markdown(STDOUT, ss) do |md_io|
    file.each_line do |line|
      md_io.puts(line)
    end
  end
end
