require "./spec_helper"

Spectator.describe Termify do
  describe ".render_markdown" do
    it "yields a Renderer to the block" do
      io = IO::Memory.new
      Termify.render_markdown(io) do |md|
        expect(md).to be_a(Termify::Markdown::Renderer)
      end
    end

    it "closes the renderer after the block returns" do
      io = IO::Memory.new
      renderer = uninitialized Termify::Markdown::Renderer
      Termify.render_markdown(io) do |md|
        renderer = md
      end
      expect(renderer.closed?).to be_true
    end

    it "writes output to the provided IO" do
      io = IO::Memory.new
      Termify.render_markdown(io) do |md|
        md << "hello world\n"
      end
      expect(io.to_s).to contain("hello world")
    end

    it "renders markdown markup correctly" do
      io = IO::Memory.new
      Termify.render_markdown(io) do |md|
        md << "**bold text**\n"
      end
      expect(io.to_s).to contain(Termify::ANSI::BOLD)
      expect(io.to_s).to contain("bold text")
    end

    it "accepts a custom stylesheet" do
      io = IO::Memory.new
      custom = Termify::Markdown::Stylesheet.new({
        :paragraph => {fg: Colorize::ColorANSI::Cyan},
      })
      Termify.render_markdown(io, custom) do |md|
        md << "some text\n"
      end
      expect(io.to_s).to contain("\e[36m")
    end
  end

  describe ".markdown_stylesheet" do
    it "returns a Stylesheet" do
      expect(Termify.markdown_stylesheet({} of Symbol => NamedTuple())).to be_a(Termify::Markdown::Stylesheet)
    end

    it "defaults to Stylesheet.default for unmapped entries" do
      sheet = Termify.markdown_stylesheet({} of Symbol => NamedTuple())
      # H1 is bold in the default theme
      expect(sheet[Termify::Markdown::BlockElement::H1].bold?).to be_true
    end

    it "applies caller-supplied overrides over the default theme" do
      sheet = Termify.markdown_stylesheet({:paragraph => {bold: true}})
      expect(sheet[Termify::Markdown::BlockElement::Paragraph].bold?).to be_true
    end

    it "does not mutate the default stylesheet when overrides are applied" do
      Termify.markdown_stylesheet({:paragraph => {bold: true}})
      expect(Termify::Markdown::Stylesheet.default[Termify::Markdown::BlockElement::Paragraph])
        .to eq(Termify::Markdown::BlockStyle::NONE)
    end

    it "accepts a custom merge: base instead of the default" do
      custom_base = Termify::Markdown::Stylesheet.new({:h1 => {italic: true}})
      sheet = Termify.markdown_stylesheet({:paragraph => {bold: true}}, custom_base)
      expect(sheet[Termify::Markdown::BlockElement::H1].italic?).to be_true
      expect(sheet[Termify::Markdown::BlockElement::Paragraph].bold?).to be_true
    end
  end
end
