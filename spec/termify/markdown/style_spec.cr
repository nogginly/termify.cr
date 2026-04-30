require "../../spec_helper"

Spectator.describe Termify::Markdown::Style do
  # ── construction ────────────────────────────────────────────────────────────

  describe "initialization" do
    it "defaults all Bool flags to false" do
      s = Termify::Markdown::Style.new
      expect(s.bold?).to be_false
      expect(s.italic?).to be_false
      expect(s.dim?).to be_false
      expect(s.underline?).to be_false
      expect(s.strikethrough?).to be_false
    end

    it "defaults all optional fields to nil" do
      s = Termify::Markdown::Style.new
      expect(s.fg).to be_nil
      expect(s.bg).to be_nil
    end

    it "accepts named arguments selectively" do
      s = Termify::Markdown::Style.new(bold: true, fg: Colorize::ColorANSI::Red)
      expect(s.bold?).to be_true
      expect(s.italic?).to be_false
      expect(s.fg).to eq(Colorize::ColorANSI::Red)
      expect(s.bg).to be_nil
    end
  end

  # ── NONE constants ──────────────────────────────────────────────────────────

  describe "BlockStyle::NONE" do
    it "is a BlockStyle with no attributes set" do
      expect(Termify::Markdown::BlockStyle::NONE.bold?).to be_false
      expect(Termify::Markdown::BlockStyle::NONE.fg).to be_nil
      expect(Termify::Markdown::BlockStyle::NONE.line_prefix).to be_nil
    end

    it "produces an empty ANSI string" do
      expect(Termify::Markdown::BlockStyle::NONE.to_ansi).to eq("")
    end
  end

  describe "InlineStyle::NONE" do
    it "is an InlineStyle with no attributes set" do
      expect(Termify::Markdown::InlineStyle::NONE.bold?).to be_false
      expect(Termify::Markdown::InlineStyle::NONE.fg).to be_nil
    end

    it "produces an empty ANSI string" do
      expect(Termify::Markdown::InlineStyle::NONE.to_ansi).to eq("")
    end
  end

  # ── #to_ansi ─────────────────────────────────────────────────────────────

  describe "#to_ansi" do
    it "returns empty string when no attributes are set" do
      expect(Termify::Markdown::Style.new.to_ansi).to eq("")
    end

    it "emits BOLD for bold: true" do
      s = Termify::Markdown::Style.new(bold: true)
      expect(s.to_ansi).to eq(Termify::ANSI::BOLD)
    end

    it "emits ITALIC for italic: true" do
      s = Termify::Markdown::Style.new(italic: true)
      expect(s.to_ansi).to eq(Termify::ANSI::ITALIC)
    end

    it "emits DIM for dim: true" do
      s = Termify::Markdown::Style.new(dim: true)
      expect(s.to_ansi).to eq(Termify::ANSI::DIM)
    end

    it "emits UNDERLINE for underline: true" do
      s = Termify::Markdown::Style.new(underline: true)
      expect(s.to_ansi).to eq(Termify::ANSI::UNDERLINE)
    end

    it "emits STRIKETHROUGH for strikethrough: true" do
      s = Termify::Markdown::Style.new(strikethrough: true)
      expect(s.to_ansi).to eq(Termify::ANSI::STRIKETHROUGH)
    end

    it "emits the fg sequence when fg is set" do
      s = Termify::Markdown::Style.new(fg: Colorize::ColorANSI::Cyan)
      expect(s.to_ansi).to eq("\e[36m")
    end

    it "emits the bg sequence when bg is set" do
      s = Termify::Markdown::Style.new(bg: Colorize::ColorANSI::Blue)
      expect(s.to_ansi).to eq("\e[44m")
    end

    it "emits SGR flags before fg before bg (canonical order)" do
      s = Termify::Markdown::Style.new(
        bold: true,
        italic: true,
        fg: Colorize::ColorANSI::Yellow,
        bg: Colorize::ColorANSI::Black
      )
      expect(s.to_ansi).to eq(
        Termify::ANSI::BOLD +
        Termify::ANSI::ITALIC +
        "\e[33m" +
        "\e[40m"
      )
    end

    it "works with 256-color fg sequences" do
      s = Termify::Markdown::Style.new(fg: Colorize::Color256.new(202))
      expect(s.to_ansi).to eq("\e[38;5;202m")
    end

    it "does not include line_prefix or line_suffix in ANSI output" do
      s = Termify::Markdown::BlockStyle.new(bold: true, line_prefix: "# ", line_suffix: " #")
      expect(s.to_ansi).to eq(Termify::ANSI::BOLD)
    end
  end

  # ── #empty? ──────────────────────────────────────────────────────────────

  describe "#empty?" do
    it "returns true for a default Style" do
      expect(Termify::Markdown::Style.new.empty?).to be_true
    end

    it "returns true when only line_prefix/line_suffix are set" do
      s = Termify::Markdown::BlockStyle.new(line_prefix: "> ", line_suffix: ".")
      expect(s.empty?).to be_true
    end

    it "returns false when bold is set" do
      expect(Termify::Markdown::Style.new(bold: true).empty?).to be_false
    end

    it "returns false when fg is set" do
      expect(Termify::Markdown::Style.new(fg: Colorize::ColorANSI::Green).empty?).to be_false
    end

    it "returns false when bg is set" do
      expect(Termify::Markdown::Style.new(bg: Colorize::ColorANSI::Red).empty?).to be_false
    end
  end

  # ── #merge ───────────────────────────────────────────────────────────────

  describe "#merge" do
    it "returns a new Style (does not mutate self)" do
      base = Termify::Markdown::Style.new(bold: true)
      other = Termify::Markdown::Style.new(italic: true)
      merged = base.merge(other)
      expect(base.italic?).to be_false # struct copy — self is never mutated
    end

    it "OR-merges Bool flags — both base and override contribute" do
      base = Termify::Markdown::Style.new(bold: true)
      other = Termify::Markdown::Style.new(italic: true)
      merged = base.merge(other)
      expect(merged.bold?).to be_true
      expect(merged.italic?).to be_true
    end

    it "override fg wins over base fg" do
      base = Termify::Markdown::Style.new(fg: Colorize::ColorANSI::Red)
      other = Termify::Markdown::Style.new(fg: Colorize::ColorANSI::Blue)
      expect(base.merge(other).fg).to eq(Colorize::ColorANSI::Blue)
    end

    it "base fg is kept when override fg is nil" do
      base = Termify::Markdown::Style.new(fg: Colorize::ColorANSI::Green)
      other = Termify::Markdown::Style.new
      expect(base.merge(other).fg).to eq(Colorize::ColorANSI::Green)
    end

    it "override bg wins over base bg" do
      base = Termify::Markdown::Style.new(bg: Colorize::ColorANSI::Black)
      other = Termify::Markdown::Style.new(bg: Colorize::ColorANSI::LightGray)
      expect(base.merge(other).bg).to eq(Colorize::ColorANSI::LightGray)
    end

    it "override line_prefix wins over base line_prefix" do
      base = Termify::Markdown::BlockStyle.new(line_prefix: "## ")
      other = Termify::Markdown::BlockStyle.new(line_prefix: "### ")
      expect(base.merge(other).line_prefix).to eq("### ")
    end

    it "base line_prefix is kept when override line_prefix is nil" do
      base = Termify::Markdown::BlockStyle.new(line_prefix: "> ")
      other = Termify::Markdown::BlockStyle.new(bold: true)
      expect(base.merge(other).line_prefix).to eq("> ")
    end

    it "merging with a zero-value style returns a style equal in value to self" do
      base = Termify::Markdown::Style.new(bold: true, fg: Colorize::ColorANSI::Cyan)
      merged = base.merge(Termify::Markdown::Style.new)
      expect(merged.bold?).to eq(base.bold?)
      expect(merged.fg).to eq(base.fg)
    end

    it "bold stays true when both sides are bold" do
      base = Termify::Markdown::Style.new(bold: true)
      other = Termify::Markdown::Style.new(bold: true)
      expect(base.merge(other).bold?).to be_true
    end
  end
end

Spectator.describe Termify::Markdown::BlockStyle do
  describe "initialization" do
    it "defaults line_prefix and line_suffix to nil" do
      s = Termify::Markdown::BlockStyle.new
      expect(s.line_prefix).to be_nil
      expect(s.line_suffix).to be_nil
    end

    it "defaults newline_before and newline_after to false" do
      s = Termify::Markdown::BlockStyle.new
      expect(s.newline_before?).to be_false
      expect(s.newline_after?).to be_false
    end

    it "accepts line_prefix and line_suffix" do
      s = Termify::Markdown::BlockStyle.new(line_prefix: "| ", line_suffix: "\n")
      expect(s.line_prefix).to eq("| ")
      expect(s.line_suffix).to eq("\n")
    end

    it "accepts newline_before and newline_after" do
      s = Termify::Markdown::BlockStyle.new(newline_before: true, newline_after: true)
      expect(s.newline_before?).to be_true
      expect(s.newline_after?).to be_true
    end
  end

  describe "#merge" do
    it "returns a BlockStyle" do
      base = Termify::Markdown::BlockStyle.new(bold: true)
      expect(base.merge(Termify::Markdown::BlockStyle.new)).to be_a(Termify::Markdown::BlockStyle)
    end

    it "picks up line_prefix from other BlockStyle" do
      base = Termify::Markdown::BlockStyle.new(line_prefix: "A")
      other = Termify::Markdown::BlockStyle.new(line_prefix: "B")
      expect(base.merge(other).line_prefix).to eq("B")
    end

    it "keeps own line_prefix when other has none" do
      base = Termify::Markdown::BlockStyle.new(line_prefix: "A")
      other = Termify::Markdown::BlockStyle.new(bold: true)
      expect(base.merge(other).line_prefix).to eq("A")
    end

    it "does not pick up line_prefix from a plain Style" do
      base = Termify::Markdown::BlockStyle.new(line_prefix: "A")
      other = Termify::Markdown::Style.new(bold: true)
      expect(base.merge(other).line_prefix).to eq("A")
    end

    it "OR-merges newline_before -- true wins" do
      base = Termify::Markdown::BlockStyle.new(newline_before: true)
      other = Termify::Markdown::BlockStyle.new
      expect(base.merge(other).newline_before?).to be_true
      expect(other.merge(base).newline_before?).to be_true
    end

    it "OR-merges newline_after -- true wins" do
      base = Termify::Markdown::BlockStyle.new(newline_after: true)
      other = Termify::Markdown::BlockStyle.new
      expect(base.merge(other).newline_after?).to be_true
    end

    it "newline_before stays false when both sides are false" do
      a = Termify::Markdown::BlockStyle.new
      b = Termify::Markdown::BlockStyle.new
      expect(a.merge(b).newline_before?).to be_false
    end
  end

  describe "#==" do
    it "is equal to another BlockStyle with same fields" do
      a = Termify::Markdown::BlockStyle.new(bold: true, line_prefix: "> ")
      b = Termify::Markdown::BlockStyle.new(bold: true, line_prefix: "> ")
      expect(a).to eq(b)
    end

    it "is not equal when line_prefix differs" do
      a = Termify::Markdown::BlockStyle.new(line_prefix: "> ")
      b = Termify::Markdown::BlockStyle.new(line_prefix: "| ")
      expect(a).not_to eq(b)
    end

    it "is not equal when newline_before differs" do
      a = Termify::Markdown::BlockStyle.new(newline_before: true)
      b = Termify::Markdown::BlockStyle.new
      expect(a).not_to eq(b)
    end

    it "is not equal when newline_after differs" do
      a = Termify::Markdown::BlockStyle.new(newline_after: true)
      b = Termify::Markdown::BlockStyle.new
      expect(a).not_to eq(b)
    end

    it "is not equal to a plain Style with same SGR fields" do
      a = Termify::Markdown::BlockStyle.new(bold: true)
      b = Termify::Markdown::Style.new(bold: true)
      expect(a).not_to eq(b)
    end
  end
end

Spectator.describe Termify::Markdown::InlineStyle do
  describe "#merge" do
    it "returns an InlineStyle" do
      base = Termify::Markdown::InlineStyle.new(bold: true)
      expect(base.merge(Termify::Markdown::InlineStyle.new)).to be_a(Termify::Markdown::InlineStyle)
    end

    it "OR-merges bool flags" do
      base = Termify::Markdown::InlineStyle.new(bold: true)
      other = Termify::Markdown::InlineStyle.new(italic: true)
      merged = base.merge(other)
      expect(merged.bold?).to be_true
      expect(merged.italic?).to be_true
    end
  end

  describe "NONE" do
    it "is an InlineStyle with no attributes" do
      expect(Termify::Markdown::InlineStyle::NONE.bold?).to be_false
      expect(Termify::Markdown::InlineStyle::NONE.fg).to be_nil
    end
  end
end
