require "../../../spec_helper"

Spectator.describe Termify::Markdown::CodeBlockStyle do
  include Termify::Markdown

  # -- NONE constant ----------------------------------------------------------

  describe "NONE" do
    it "has no SGR attributes" do
      expect(CodeBlockStyle::NONE.to_ansi).to eq("")
    end

    it "has no line_number_format" do
      expect(CodeBlockStyle::NONE.line_number_format).to be_nil
    end

    it "is the same object on repeated access -- no allocation" do
      expect(CodeBlockStyle::NONE).to be(CodeBlockStyle::NONE)
    end
  end

  # -- line_number_format -----------------------------------------------------

  describe "#line_number_format" do
    it "defaults to nil" do
      expect(CodeBlockStyle.new.line_number_format).to be_nil
    end

    it "stores the supplied format string" do
      style = CodeBlockStyle.new(line_number_format: "%3d | ")
      expect(style.line_number_format).to eq("%3d | ")
    end
  end

  # -- merge ------------------------------------------------------------------

  describe "#merge" do
    it "returns a CodeBlockStyle" do
      result = CodeBlockStyle.new.merge(CodeBlockStyle.new)
      expect(result).to be_a(CodeBlockStyle)
    end

    it "inherits line_number_format from self when other has none" do
      base = CodeBlockStyle.new(line_number_format: "%d ")
      result = base.merge(CodeBlockStyle.new)
      expect(result.line_number_format).to eq("%d ")
    end

    it "overrides line_number_format from other when other has one" do
      base = CodeBlockStyle.new(line_number_format: "%d ")
      other = CodeBlockStyle.new(line_number_format: "%3d | ")
      result = base.merge(other)
      expect(result.line_number_format).to eq("%3d | ")
    end

    it "accepts line_number_format from other when self has none" do
      base = CodeBlockStyle.new
      other = CodeBlockStyle.new(line_number_format: "%2d ")
      result = base.merge(other)
      expect(result.line_number_format).to eq("%2d ")
    end

    it "merges base BlockStyle properties correctly" do
      base = CodeBlockStyle.new(bold: true, line_number_format: "%d ")
      other = CodeBlockStyle.new(italic: true)
      result = base.merge(other)
      expect(result.bold?).to be_true
      expect(result.italic?).to be_true
      expect(result.line_number_format).to eq("%d ")
    end

    it "returns nil line_number_format when neither side has one" do
      result = CodeBlockStyle.new.merge(CodeBlockStyle.new)
      expect(result.line_number_format).to be_nil
    end
  end

  # -- equality ---------------------------------------------------------------

  describe "#==" do
    it "equals another CodeBlockStyle with the same fields" do
      a = CodeBlockStyle.new(bold: true, line_number_format: "%d ")
      b = CodeBlockStyle.new(bold: true, line_number_format: "%d ")
      expect(a).to eq(b)
    end

    it "is not equal when line_number_format differs" do
      a = CodeBlockStyle.new(line_number_format: "%d ")
      b = CodeBlockStyle.new(line_number_format: "%3d | ")
      expect(a).to_not eq(b)
    end

    it "is not equal when gutter_style differs" do
      a = CodeBlockStyle.new(gutter_style: InlineStyle.new(dim: true))
      b = CodeBlockStyle.new(gutter_style: nil)
      expect(a).to_not eq(b)
    end

    it "is not equal to a plain BlockStyle even with identical base fields" do
      a = CodeBlockStyle.new(bold: true)
      b = BlockStyle.new(bold: true)
      expect(a).to_not eq(b)
    end

    it "is commutative -- BlockStyle != CodeBlockStyle" do
      a = CodeBlockStyle.new(bold: true)
      b = BlockStyle.new(bold: true)
      expect(b).to_not eq(a)
    end
  end

  # -- gutter_style -----------------------------------------------------------

  describe "#gutter_style" do
    it "defaults to nil" do
      expect(CodeBlockStyle.new.gutter_style).to be_nil
    end

    it "stores a supplied InlineStyle" do
      gs = InlineStyle.new(dim: true)
      style = CodeBlockStyle.new(gutter_style: gs)
      expect(style.gutter_style).to eq(gs)
    end
  end

  describe "#merge with gutter_style" do
    it "inherits gutter_style from self when other has none" do
      gs = InlineStyle.new(dim: true)
      base = CodeBlockStyle.new(gutter_style: gs)
      result = base.merge(CodeBlockStyle.new)
      expect(result.gutter_style).to eq(gs)
    end

    it "overrides gutter_style from other when other has one" do
      gs_a = InlineStyle.new(dim: true)
      gs_b = InlineStyle.new(italic: true)
      result = CodeBlockStyle.new(gutter_style: gs_a).merge(CodeBlockStyle.new(gutter_style: gs_b))
      expect(result.gutter_style).to eq(gs_b)
    end

    it "leaves gutter_style nil when neither side has one" do
      result = CodeBlockStyle.new.merge(CodeBlockStyle.new)
      expect(result.gutter_style).to be_nil
    end
  end

  # -- highlight_theme --------------------------------------------------------

  describe "#highlight_theme" do
    it "defaults to nil" do
      expect(CodeBlockStyle.new.highlight_theme).to be_nil
    end

    it "stores the supplied theme name" do
      style = CodeBlockStyle.new(highlight_theme: "catppuccin-macchiato")
      expect(style.highlight_theme).to eq("catppuccin-macchiato")
    end
  end

  describe "#merge with highlight_theme" do
    it "inherits highlight_theme from self when other has none" do
      base = CodeBlockStyle.new(highlight_theme: "monokai")
      result = base.merge(CodeBlockStyle.new)
      expect(result.highlight_theme).to eq("monokai")
    end

    it "overrides highlight_theme from other when other has one" do
      base = CodeBlockStyle.new(highlight_theme: "monokai")
      other = CodeBlockStyle.new(highlight_theme: "catppuccin-macchiato")
      expect(base.merge(other).highlight_theme).to eq("catppuccin-macchiato")
    end

    it "leaves highlight_theme nil when neither side has one" do
      expect(CodeBlockStyle.new.merge(CodeBlockStyle.new).highlight_theme).to be_nil
    end
  end

  describe "#== with highlight_theme" do
    it "is not equal when highlight_theme differs" do
      a = CodeBlockStyle.new(highlight_theme: "monokai")
      b = CodeBlockStyle.new(highlight_theme: "catppuccin-macchiato")
      expect(a).to_not eq(b)
    end

    it "is equal when highlight_theme matches" do
      a = CodeBlockStyle.new(highlight_theme: "monokai")
      b = CodeBlockStyle.new(highlight_theme: "monokai")
      expect(a).to eq(b)
    end
  end
end
