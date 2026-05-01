require "../src/termify"

USAGE = "Usage: md2term <MARKDOWNFILE>\nRead a Markdown file and render to terminal."
md_file = ARGV[0]? || abort(USAGE)

ss = Termify.markdown_stylesheet({
  "h1"          => {bold: true, line_prefix: "# ".colorize(:dark_gray).to_s, newline_after: true},
  "h2"          => {bold: true, line_prefix: "## ".colorize(:dark_gray).to_s, newline_after: true, newline_before: true},
  "h3"          => {bold: true, line_prefix: "### ".colorize(:dark_gray).to_s, newline_after: true, newline_before: true},
  "h4"          => {bold: true, line_prefix: "#### ".colorize(:dark_gray).to_s},
  "h5"          => {bold: true},
  "h6"          => {bold: true},
  "code_block"  => {fg: :light_cyan, line_prefix: "` "},
  "code_inline" => {fg: :red},
  "html_tag"    => {dim: true},
  "block_html"  => {dim: true},
  "list_item"   => {newline_after: true, newline_before: true},
  "block_quote" => {line_prefix: "│ ", newline_after: true, newline_before: true},
})

File.open(md_file, "r") do |file|
  Termify.render_markdown(STDOUT, ss) do |md_io|
    file.each_line do |line|
      md_io.puts(line)
    end
  end
end
