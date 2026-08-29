require "../../../spec_helper"

private def strip_ansi(text : String) : String
  text.gsub(/\e\[[0-9;]*m/, "")
end

private def inline_renderer : Termify::Markdown::InlineRenderer
  Termify::Markdown::InlineRenderer.new(Termify::Markdown::Stylesheet.default)
end

private NO_STYLE = Termify::Markdown::BlockStyle::NONE

# Direct unit specs for the inline scanner, now that it is testable without
# driving a whole Renderer. Inline behaviour in context is still covered
# through Renderer in renderer/inline_spec.cr; these cover the scanner alone.
Spectator.describe Termify::Markdown::InlineRenderer do
  describe "#render" do
    it "passes text through untouched when there is no markup" do
      expect(inline_renderer.render("plain text", NO_STYLE)).to eq("plain text")
    end

    it "consumes emphasis delimiters" do
      expect(strip_ansi(inline_renderer.render("**bold**", NO_STYLE))).to eq("bold")
      expect(strip_ansi(inline_renderer.render("*italic*", NO_STYLE))).to eq("italic")
      expect(strip_ansi(inline_renderer.render("~~struck~~", NO_STYLE))).to eq("struck")
    end

    it "emits a styling sequence for an emphasis span" do
      expect(inline_renderer.render("**bold**", NO_STYLE)).to contain(Termify::ANSI::BOLD)
    end

    it "leaves mid-word underscores alone" do
      expect(inline_renderer.render("snake_case_name", NO_STYLE)).to eq("snake_case_name")
    end

    it "treats an unclosed delimiter as a literal" do
      expect(strip_ansi(inline_renderer.render("2 * 3 = 6", NO_STYLE))).to eq("2 * 3 = 6")
      expect(strip_ansi(inline_renderer.render("a ~ b", NO_STYLE))).to eq("a ~ b")
    end

    it "does not interpret markup inside a code span" do
      expect(strip_ansi(inline_renderer.render("`**not bold**`", NO_STYLE))).to eq("**not bold**")
    end

    it "suppresses the URL of a link and keeps its text" do
      rendered = strip_ansi(inline_renderer.render("see [the docs](https://example.com) now", NO_STYLE))
      expect(rendered).to eq("see the docs now")
    end

    it "renders markup nested inside link text" do
      expect(strip_ansi(inline_renderer.render("[**bold link**](url)", NO_STYLE))).to eq("bold link")
    end

    it "emits an HTML tag verbatim" do
      expect(strip_ansi(inline_renderer.render("a <br/> b", NO_STYLE))).to eq("a <br/> b")
    end

    it "restores the block style after a span closes" do
      style = Termify::Markdown::BlockStyle.new(fg: Colorize::ColorANSI::Red)
      rendered = inline_renderer.render("a **b** c", style)
      expect(rendered).to contain(Termify::ANSI::RESET)
      expect(rendered).to contain(style.to_ansi)
    end

    it "handles nested spans of different kinds" do
      expect(strip_ansi(inline_renderer.render("**bold and *italic* here**", NO_STYLE))).to eq("bold and italic here")
    end

    it "returns an empty string for empty input" do
      expect(inline_renderer.render("", NO_STYLE)).to eq("")
    end
  end
end
