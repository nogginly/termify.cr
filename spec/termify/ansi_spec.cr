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

  describe ".color_supported?" do
    context "when NO_COLOR is set" do
      it "returns false" do
        with_env({"NO_COLOR" => ""}) do
          expect(Termify::ANSI.color_supported?).to be_false
        end
      end
    end

    context "when TERM=dumb" do
      it "returns false" do
        with_env({"TERM" => "dumb"}) do
          expect(Termify::ANSI.color_supported?).to be_false
        end
      end
    end

    context "when COLORTERM is set" do
      it "returns true" do
        with_env({"COLORTERM" => "truecolor"}) do
          expect(Termify::ANSI.color_supported?).to be_true
        end
      end
    end
  end

  describe ".truecolor_supported?" do
    context "when COLORTERM=truecolor" do
      it "returns true" do
        with_env({"COLORTERM" => "truecolor"}) do
          expect(Termify::ANSI.truecolor_supported?).to be_true
        end
      end
    end

    context "when COLORTERM=24bit" do
      it "returns true" do
        with_env({"COLORTERM" => "24bit"}) do
          expect(Termify::ANSI.truecolor_supported?).to be_true
        end
      end
    end

    context "when COLORTERM is absent" do
      it "returns false" do
        with_env({"COLORTERM" => nil}) do
          expect(Termify::ANSI.truecolor_supported?).to be_false
        end
      end
    end
  end
end

# Minimal ENV helper — saves/restores vars around a block.
private def with_env(vars : Hash(String, String?), &)
  saved = {} of String => String?
  begin
    vars.each do |key, val|
      saved[key] = ENV[key]?
      if val
        ENV[key] = val
      else
        ENV.delete(key)
      end
    end
    yield
  ensure
    saved.each do |key, val|
      if val
        ENV[key] = val
      else
        ENV.delete(key)
      end
    end
  end
end
