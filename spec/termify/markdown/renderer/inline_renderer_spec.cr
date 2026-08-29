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

  describe "#runs" do
    it "returns a single unstyled run for plain text" do
      runs = inline_renderer.runs("plain text", NO_STYLE)
      expect(runs.size).to eq(1)
      expect(runs.first.text).to eq("plain text")
      expect(runs.first.ansi).to be_empty
    end

    it "returns no runs for empty input" do
      expect(inline_renderer.runs("", NO_STYLE)).to be_empty
    end

    it "never puts escape sequences in run text" do
      runs = inline_renderer.runs("a **b** c *d* e", NO_STYLE)
      runs.each do |run|
        expect(run.text).not_to contain("\e")
      end
    end

    it "joins back to the visible text" do
      runs = inline_renderer.runs("a **b** and `c` and [d](url)", NO_STYLE)
      expect(runs.map(&.text).join).to eq("a b and c and d")
    end

    it "marks the styled span and only the styled span" do
      runs = inline_renderer.runs("plain **bold** plain", NO_STYLE)
      bold = runs.select { |run| run.ansi.includes?(Termify::ANSI::BOLD) }
      expect(bold.map(&.text).join).to eq("bold")
    end

    it "carries the full active sequence, not a delta" do
      style = Termify::Markdown::BlockStyle.new(fg: Colorize::ColorANSI::Red)
      runs = inline_renderer.runs("a **b** c", style)
      bold = runs.select { |run| run.text == "b" }
      expect(bold.size).to eq(1)
      # The bold run must also carry the block style, so it can stand alone.
      expect(bold.first.ansi).to contain(Termify::ANSI::BOLD)
      expect(bold.first.ansi).to contain(style.to_ansi)
    end

    it "carries the block style on every run, including the first" do
      style = Termify::Markdown::BlockStyle.new(fg: Colorize::ColorANSI::Red)
      runs = inline_renderer.runs("**bold first** then plain", style)
      expect(runs).not_to be_empty
      runs.each do |run|
        expect(run.ansi).to contain(style.to_ansi)
      end
    end

    it "does not style a code span's content as emphasis" do
      runs = inline_renderer.runs("`**not bold**`", NO_STYLE)
      expect(runs.map(&.text).join).to eq("**not bold**")
    end

    it "styles text nested inside a link" do
      runs = inline_renderer.runs("[**bold link**](url)", NO_STYLE)
      expect(runs.map(&.text).join).to eq("bold link")
      expect(runs.any? { |run| run.ansi.includes?(Termify::ANSI::BOLD) }).to be_true
    end
  end

  describe "#plain" do
    it "strips markup and emits no escapes" do
      expect(inline_renderer.plain("a **b** and `c`", NO_STYLE)).to eq("a b and c")
    end

    it "agrees with the visible text of #render" do
      text = "mix of **bold**, *italic*, `code` and [links](url)"
      rendered = strip_ansi(inline_renderer.render(text, NO_STYLE))
      expect(inline_renderer.plain(text, NO_STYLE)).to eq(rendered)
    end
  end
end
