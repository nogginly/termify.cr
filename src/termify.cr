require "./termify/*"
require "./termify/markdown/*"
require "./termify/tui/*"

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

  # Convenience method to define a new Markdown stylesheet via the hash map of element names to
  # respective style definitions. Merges with the default stylesheet by default.
  def self.markdown_stylesheet(styles : Hash(Symbol | String, NamedTuple),
                               merge = Markdown::Stylesheet.default)
    Markdown::Stylesheet.new(styles, merge)
  end

  # Get the singleton instance of `Terminal`
  def self.terminal
    @@terminal ||= Terminal.new
  end

  # :nodoc:
  module Version
    VERSION    = {{ `shards version #{__DIR__}`.chomp.stringify }}
    PRERELEASE = VERSION.match(/^\d+\.\d+\.\d+$/).nil?
  end
end
