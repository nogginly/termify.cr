require "../../../spec_helper"

Spectator.describe Termify::Markdown::CodeRenderer do
  include Termify
  include Termify::Markdown

  def make_renderer(language = "", style = CodeBlockStyle::NONE, indent = "") : {CodeRenderer, IO::Memory}
    io = IO::Memory.new
    cr = CodeRenderer.new(language, style, io, indent)
    {cr, io}
  end

  # -- language ---------------------------------------------------------------

  describe "#language" do
    it "stores the language tag" do
      cr, _ = make_renderer(language: "crystal")
      expect(cr.language).to eq("crystal")
    end

    it "stores an empty string when no language tag is given" do
      cr, _ = make_renderer(language: "")
      expect(cr.language).to eq("")
    end
  end

  # -- feed -------------------------------------------------------------------

  describe "#feed" do
    it "emits the line followed by a newline" do
      cr, io = make_renderer
      cr.feed("some code")
      expect(io.to_s).to eq("some code\n")
    end

    it "emits multiple lines in order" do
      cr, io = make_renderer
      cr.feed("line one")
      cr.feed("line two")
      expect(io.to_s).to eq("line one\nline two\n")
    end

    it "preserves leading whitespace in lines" do
      cr, io = make_renderer
      cr.feed("  indented")
      expect(io.to_s).to contain("  indented")
    end

    it "does not apply inline parsing -- markers are emitted verbatim" do
      cr, io = make_renderer
      cr.feed("**not bold**")
      expect(io.to_s).to contain("**not bold**")
    end

    it "applies the block style ANSI sequence" do
      style = CodeBlockStyle.new(bold: true)
      cr, io = make_renderer(style: style)
      cr.feed("styled")
      expect(io.to_s).to contain(ANSI::BOLD)
    end

    it "emits a reset after the line when a style is active" do
      style = CodeBlockStyle.new(bold: true)
      cr, io = make_renderer(style: style)
      cr.feed("styled")
      expect(io.to_s).to contain(ANSI::RESET)
    end

    it "emits no ANSI sequences when the style is NONE" do
      cr, io = make_renderer(style: CodeBlockStyle::NONE)
      cr.feed("plain")
      expect(io.to_s).to eq("plain\n")
    end

    it "prepends the line_prefix from the style" do
      style = CodeBlockStyle.new(line_prefix: "  ")
      cr, io = make_renderer(style: style)
      cr.feed("code")
      expect(io.to_s).to contain("  code")
    end

    it "prepends the indent string before the prefix" do
      style = CodeBlockStyle.new(line_prefix: "> ")
      cr, io = make_renderer(style: style, indent: "    ")
      cr.feed("code")
      expect(io.to_s).to contain("    > code")
    end

    it "prepends only the indent when style has no prefix" do
      cr, io = make_renderer(indent: "  ")
      cr.feed("code")
      expect(io.to_s).to contain("  code")
    end
  end

  # -- close ------------------------------------------------------------------

  describe "#close" do
    it "does not emit anything extra" do
      cr, io = make_renderer
      cr.feed("code")
      output_before = io.to_s
      cr.close
      expect(io.to_s).to eq(output_before)
    end
  end

  # -- line numbers -----------------------------------------------------------

  describe "line numbers" do
    it "emits no gutter when line_number_format is nil" do
      cr, io = make_renderer(style: CodeBlockStyle.new(line_number_format: nil))
      cr.feed("code")
      expect(io.to_s).to eq("code\n")
    end

    it "prepends the formatted line number on each line" do
      cr, io = make_renderer(style: CodeBlockStyle.new(line_number_format: "%2d | "))
      cr.feed("first")
      cr.feed("second")
      lines = io.to_s.lines
      expect(lines[0]).to eq(" 1 | first")
      expect(lines[1]).to eq(" 2 | second")
    end

    it "increments the line number for each feed call" do
      cr, io = make_renderer(style: CodeBlockStyle.new(line_number_format: "%d "))
      3.times { |i| cr.feed("line #{i + 1}") }
      expect(io.to_s).to contain("1 line 1")
      expect(io.to_s).to contain("2 line 2")
      expect(io.to_s).to contain("3 line 3")
    end

    it "places the gutter before the line_prefix" do
      style = CodeBlockStyle.new(line_number_format: "%d:", line_prefix: "  ")
      cr, io = make_renderer(style: style)
      cr.feed("code")
      expect(io.to_s).to contain("1:  code")
    end

    it "places the gutter after the indent" do
      cr, io = make_renderer(style: CodeBlockStyle.new(line_number_format: "%d "), indent: "  ")
      cr.feed("code")
      expect(io.to_s).to start_with("  1 code")
    end
  end
end
