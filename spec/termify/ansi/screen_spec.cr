require "../../spec_helper"

Spectator.describe Termify::ANSI::Screen do
  describe ".switch_to_alternate" do
    it "returns the alt screen enable sequence" do
      expect(Termify::ANSI::Screen.switch_to_alternate).to eq("\e[?1049h")
    end
  end

  describe ".switch_to_default" do
    it "returns the alt screen disable sequence" do
      expect(Termify::ANSI::Screen.switch_to_default).to eq("\e[?1049l")
    end
  end

  describe ".scroll_region" do
    it "returns the region sequence for the given rows" do
      expect(Termify::ANSI::Screen.scroll_region(4, 9)).to eq("\e[4;9r")
    end

    it "returns a single row region when top and bottom match" do
      expect(Termify::ANSI::Screen.scroll_region(7, 7)).to eq("\e[7;7r")
    end
  end

  describe ".reset_scroll_region" do
    it "returns the sequence restoring full screen scrolling" do
      expect(Termify::ANSI::Screen.reset_scroll_region).to eq("\e[r")
    end
  end
end
