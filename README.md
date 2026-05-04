# Termify.cr

A Crystal shard for rendering Markdown to terminal, with an emphasis on _streaming_ for the most part.

## AI Usage

See [DISCLOSURE](DISCLOSURE.md) for how I used AI for this project.

## Installation

1. Add the dependency to your `shard.yml`:

   ```yaml
   dependencies:
     termify:
       github: nogginly/termify.cr
   ```

2. Run `shards install`

## Usage

```crystal
require "termify"
```

### Rendering Markdown

```crystal
Termify.render_markdown do |io|
  io.puts "# Hello"
  io << "_Hello_, **World!**
end
```

### Custom stylesheet

Here's an example of a custom stylesheet (from [`md2term`](./samples/md2term.cr) sample):

```crystal
STYLESHEET = Termify.markdown_stylesheet({
  "h1"         => {
    bold: true,
    line_prefix: "# ".colorize(:dark_gray).to_s,
    newline_after: true
  },
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

Termify.render_markdown(STDOUT, STYLESHEET) do |md_io|
  # send your Markdown to `md_io`
end

```

## Credits

- [Tablo](https://github.com/hutou/tablo), for the table rendering
- [Tartrazine](https://github.com/ralsina/tartrazine), for the code syntax highlighting

## Development

See [DEVELOPMENT](./DEVELOPMENT.md)

## Contributions, by invitation!

*With apologies*, at this time contributions are *by invitation only* and limited to people I know and see often.

These are early days for _Termify_ and I am busy with family and work.

At this time I want to work on this at a manageable pace.
