require "../../spec_helper"

Spectator.describe Termify::ANSI::Mouse do
  describe ".mouse_enable" do
    it "returns the sequence enabling all mouse modes" do
      expect(Termify::ANSI::Mouse.enable).to eq("\e[?1000h\e[?1002h\e[?1003h\e[?1015h\e[?1006h")
    end
  end

  describe ".mouse_disable" do
    it "returns the sequence disabling all mouse modes" do
      expect(Termify::ANSI::Mouse.disable).to eq("\e[?1000l\e[?1002l\e[?1003l\e[?1015l\e[?1006l")
    end
  end
end
