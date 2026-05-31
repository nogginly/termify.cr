require "../../spec_helper"

Spectator.describe Termify::ANSI::Cursor do
  describe ".up" do
    it "returns short form for default (0)" do
      expect(Termify::ANSI::Cursor.up).to eq("\e[A")
    end

    it "returns short form for n=1" do
      expect(Termify::ANSI::Cursor.up(1)).to eq("\e[A")
    end

    it "returns long form for n>1" do
      expect(Termify::ANSI::Cursor.up(5)).to eq("\e[5A")
    end
  end

  describe ".down" do
    it "returns short form for default (0)" do
      expect(Termify::ANSI::Cursor.down).to eq("\e[B")
    end

    it "returns short form for n=1" do
      expect(Termify::ANSI::Cursor.down(1)).to eq("\e[B")
    end

    it "returns long form for n>1" do
      expect(Termify::ANSI::Cursor.down(3)).to eq("\e[3B")
    end
  end

  describe ".right" do
    it "returns short form for default (0)" do
      expect(Termify::ANSI::Cursor.right).to eq("\e[C")
    end

    it "returns short form for n=1" do
      expect(Termify::ANSI::Cursor.right(1)).to eq("\e[C")
    end

    it "returns long form for n>1" do
      expect(Termify::ANSI::Cursor.right(4)).to eq("\e[4C")
    end
  end

  describe ".left" do
    it "returns short form for default (0)" do
      expect(Termify::ANSI::Cursor.left).to eq("\e[D")
    end

    it "returns short form for n=1" do
      expect(Termify::ANSI::Cursor.left(1)).to eq("\e[D")
    end

    it "returns long form for n>1" do
      expect(Termify::ANSI::Cursor.left(2)).to eq("\e[2D")
    end
  end

  describe ".to" do
    it "returns home sequence when both are default (0)" do
      expect(Termify::ANSI::Cursor.to).to eq("\e[H")
    end

    it "returns home sequence when both are 1" do
      expect(Termify::ANSI::Cursor.to(1, 1)).to eq("\e[H")
    end

    it "returns positioned sequence for explicit coords" do
      expect(Termify::ANSI::Cursor.to(10, 5)).to eq("\e[5;10H")
    end

    it "returns positioned sequence when only x > 1" do
      expect(Termify::ANSI::Cursor.to(3, 0)).to eq("\e[0;3H")
    end

    it "returns positioned sequence when only y > 1" do
      expect(Termify::ANSI::Cursor.to(0, 4)).to eq("\e[4;0H")
    end
  end

  describe ".save" do
    it "returns the save sequence" do
      expect(Termify::ANSI::Cursor.save).to eq("\e7")
    end
  end

  describe ".restore" do
    it "returns the restore sequence" do
      expect(Termify::ANSI::Cursor.restore).to eq("\e8")
    end
  end

  describe ".hide" do
    it "returns the hide sequence" do
      expect(Termify::ANSI::Cursor.hide).to eq("\e[?25l")
    end
  end

  describe ".show" do
    it "returns the show sequence" do
      expect(Termify::ANSI::Cursor.show).to eq("\e[?25h")
    end
  end
end
