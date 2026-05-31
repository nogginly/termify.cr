require "../../spec_helper"

Spectator.describe Termify::ANSI::Clear do
  describe ".clear_screen" do
    it "clears all and homes cursor by default" do
      expect(Termify::ANSI::Clear.screen).to eq("\e[H\e[2J")
    end

    it "clears all with Erase::All" do
      expect(Termify::ANSI::Clear.screen(Termify::ANSI::Erase::All)).to eq("\e[H\e[2J")
    end

    it "clears before cursor with Erase::Before" do
      expect(Termify::ANSI::Clear.screen(Termify::ANSI::Erase::Before)).to eq("\e[1J")
    end

    it "clears after cursor with Erase::After" do
      expect(Termify::ANSI::Clear.screen(Termify::ANSI::Erase::After)).to eq("\e[0J")
    end
  end

  describe ".clear_line" do
    it "clears entire line by default" do
      expect(Termify::ANSI::Clear.line).to eq("\e[2K")
    end

    it "clears entire line with Erase::All" do
      expect(Termify::ANSI::Clear.line(Termify::ANSI::Erase::All)).to eq("\e[2K")
    end

    it "clears before cursor with Erase::Before" do
      expect(Termify::ANSI::Clear.line(Termify::ANSI::Erase::Before)).to eq("\e[1K")
    end

    it "clears after cursor with Erase::After" do
      expect(Termify::ANSI::Clear.line(Termify::ANSI::Erase::After)).to eq("\e[0K")
    end
  end
end
