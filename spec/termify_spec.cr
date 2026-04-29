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
end
