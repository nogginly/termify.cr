require "../spec_helper"

Spectator.describe Termify::ANSI do
  describe "constants" do
    it "RESET is the SGR reset sequence" do
      expect(Termify::ANSI::RESET).to eq("\e[0m")
    end

    it "BOLD is SGR 1" do
      expect(Termify::ANSI::BOLD).to eq("\e[1m")
    end

    it "ITALIC is SGR 3" do
      expect(Termify::ANSI::ITALIC).to eq("\e[3m")
    end

    it "UNDERLINE is SGR 4" do
      expect(Termify::ANSI::UNDERLINE).to eq("\e[4m")
    end

    it "STRIKETHROUGH is SGR 9" do
      expect(Termify::ANSI::STRIKETHROUGH).to eq("\e[9m")
    end
  end

  describe ".fg (Color256)" do
    it "produces the correct 256-color foreground sequence" do
      expect(Termify::ANSI.fg(Colorize::Color256.new(196))).to eq("\e[38;5;196m")
    end
  end

  describe ".bg (Color256)" do
    it "produces the correct 256-color background sequence" do
      expect(Termify::ANSI.bg(Colorize::Color256.new(21))).to eq("\e[48;5;21m")
    end
  end

  describe ".fg (ColorRGB)" do
    it "produces the correct truecolor foreground sequence" do
      expect(Termify::ANSI.fg(Colorize::ColorRGB.new(255, 128, 0))).to eq("\e[38;2;255;128;0m")
    end
  end

  describe ".bg (ColorRGB)" do
    it "produces the correct truecolor background sequence" do
      expect(Termify::ANSI.bg(Colorize::ColorRGB.new(0, 0, 0))).to eq("\e[48;2;0;0;0m")
    end
  end

  describe ".sequence" do
    it "concatenates codes" do
      expect(Termify::ANSI.sequence(Termify::ANSI::BOLD, Termify::ANSI::ITALIC))
        .to eq("\e[1m\e[3m")
    end

    it "returns a single code unchanged" do
      expect(Termify::ANSI.sequence(Termify::ANSI::UNDERLINE)).to eq("\e[4m")
    end
  end

  describe ".reset_and_replay" do
    it "returns bare RESET for an empty stack" do
      expect(Termify::ANSI.reset_and_replay([] of String)).to eq("\e[0m")
    end

    it "prepends RESET before all stack entries" do
      stack = [Termify::ANSI::BOLD, Termify::ANSI::ITALIC]
      expect(Termify::ANSI.reset_and_replay(stack)).to eq("\e[0m\e[1m\e[3m")
    end

    it "does not mutate the stack" do
      stack = [Termify::ANSI::BOLD]
      Termify::ANSI.reset_and_replay(stack)
      expect(stack.size).to eq(1)
    end
  end

  describe "ANSI::Color256 enum" do
    # Enum values are auto-assigned from 0; spot-check canonical 256-color indices.
    it "Black is index 0" do
      expect(Termify::ANSI::Color256::Black.value).to eq(0)
    end

    it "Red is index 9" do
      expect(Termify::ANSI::Color256::Red.value).to eq(9)
    end

    it "Blue is index 12" do
      expect(Termify::ANSI::Color256::Blue.value).to eq(12)
    end

    it "White is index 15" do
      expect(Termify::ANSI::Color256::White.value).to eq(15)
    end

    describe ".fg" do
      it "produces the correct 256-color foreground sequence for a named Color256" do
        expect(Termify::ANSI.fg(Termify::ANSI::Color256::Red)).to eq("\e[38;5;9m")
      end

      it "produces the correct 256-color foreground sequence for a high-index Color256" do
        # Grey93 is the last entry, index 255
        expect(Termify::ANSI.fg(Termify::ANSI::Color256::Grey93)).to eq("\e[38;5;255m")
      end
    end

    describe ".bg" do
      it "produces the correct 256-color background sequence for a named Color256" do
        expect(Termify::ANSI.bg(Termify::ANSI::Color256::Blue)).to eq("\e[48;5;12m")
      end
    end
  end

  describe ".repeat" do
    it "returns empty string for n=0" do
      expect(Termify::ANSI.repeat("-", 0)).to eq("")
    end

    it "returns empty string for negative n" do
      expect(Termify::ANSI.repeat("-", -1)).to eq("")
    end

    it "returns the char itself for n=1" do
      expect(Termify::ANSI.repeat("-", 1)).to eq("-")
    end

    it "returns char + REP sequence for n>1" do
      expect(Termify::ANSI.repeat("-", 3)).to eq("-\e[2b")
    end

    it "REP count is n-1" do
      expect(Termify::ANSI.repeat("*", 5)).to eq("*\e[4b")
    end
  end
end
