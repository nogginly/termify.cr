require "./termify/*"
require "./termify/markdown/*"

module Termify
  # Render Markdown to an ANSI-compatible terminal via the given `io`
  # (defaults to `STDIO`). The given block will be passed the renderer,
  # itself an `IO` as an argument. The renderer will be automatically
  # closed when the block returns.
  def self.render_markdown(io = STDOUT, style_sheet = Markdown::Stylesheet.default, &) : Nil
    md_io = Markdown::Renderer.new(io, style_sheet)
    yield md_io
    md_io.close
  end
end
