require "../../../spec_helper"

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
