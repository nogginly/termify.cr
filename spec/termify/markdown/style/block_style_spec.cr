require "../../../spec_helper"

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
