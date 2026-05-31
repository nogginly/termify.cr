require "../../spec_helper"

Spectator.describe Termify::ANSI::Screen do
  describe ".switch_to_alt_screen" do
    it "returns the alt screen enable sequence" do
      expect(Termify::ANSI::Screen.switch_to_alt_screen).to eq("\e[?1049h")
    end
  end

  describe ".switch_to_normal_screen" do
    it "returns the alt screen disable sequence" do
      expect(Termify::ANSI::Screen.switch_to_normal_screen).to eq("\e[?1049l")
    end
  end
end
