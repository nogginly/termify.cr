require "../spec_helper"

# A terminal whose ends are in memory, answering the cursor query with `row`.
private class ScriptedTerminal < Termify::Terminal
  def self.at_row(row : Int32, output = IO::Memory.new)
    new(IO::Memory.new("\e[#{row};1R"), output)
  end

  def interactive? : Bool
    true
  end
end

Spectator.describe Termify::ScrollRegion do
  describe "#initialize" do
    it "clamps a height below the minimum" do
      region = Termify::ScrollRegion.new(ScriptedTerminal.at_row(1), 1)
      expect(region.lines).to eq(3)
    end

    it "clamps a height above the maximum" do
      region = Termify::ScrollRegion.new(ScriptedTerminal.at_row(1), 99)
      expect(region.lines).to eq(10)
    end

    it "is not active before starting" do
      region = Termify::ScrollRegion.new(ScriptedTerminal.at_row(1), 5)
      expect(region.active?).to be_false
    end
  end

  describe "#start" do
    it "reserves the region, queries the row, then confines scrolling to it" do
      written = IO::Memory.new
      region = Termify::ScrollRegion.new(ScriptedTerminal.at_row(12, written), 3)

      region.start

      expect(written.to_s).to eq("\n\n\n\e[3A\e[6n\e[12;14r\e[12;1H")
    end

    it "becomes active" do
      region = Termify::ScrollRegion.new(ScriptedTerminal.at_row(12), 3)
      region.start
      expect(region.active?).to be_true
    end

    it "falls back to the default row when the reply is unintelligible" do
      written = IO::Memory.new
      term = ScriptedTerminal.new(IO::Memory.new("nonsense"), written)
      region = Termify::ScrollRegion.new(term, 3)

      region.start

      expect(written.to_s).to end_with("\e[1;3r\e[H")
    end
  end

  describe "#stop" do
    it "restores full screen scrolling and moves below the region" do
      written = IO::Memory.new
      region = Termify::ScrollRegion.new(ScriptedTerminal.at_row(12, written), 3)
      region.start
      written.clear

      region.stop

      expect(written.to_s).to eq("\e[r\e[15;1H")
    end

    it "moves to the top of the region when asked" do
      written = IO::Memory.new
      region = Termify::ScrollRegion.new(ScriptedTerminal.at_row(12, written), 3)
      region.start
      written.clear

      region.stop(top: true)

      expect(written.to_s).to eq("\e[r\e[12;1H")
    end

    it "is no longer active" do
      region = Termify::ScrollRegion.new(ScriptedTerminal.at_row(12), 3)
      region.start
      region.stop
      expect(region.active?).to be_false
    end
  end
end
