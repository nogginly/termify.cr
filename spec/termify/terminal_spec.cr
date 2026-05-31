require "../spec_helper"

Spectator.describe Termify::Terminal do
  describe ".color_supported?" do
    context "when NO_COLOR is set" do
      it "returns false" do
        with_env({"NO_COLOR" => ""}) do
          expect(Termify.terminal.color_supported?).to be_false
        end
      end
    end

    context "when TERM=dumb" do
      it "returns false" do
        with_env({"TERM" => "dumb"}) do
          expect(Termify.terminal.color_supported?).to be_false
        end
      end
    end

    context "when COLORTERM is set" do
      it "returns true" do
        with_env({"COLORTERM" => "truecolor"}) do
          expect(Termify.terminal.color_supported?).to be_true
        end
      end
    end

    context "when no suppressing env vars are set" do
      it "returns true by default" do
        with_env({"NO_COLOR" => nil, "TERM" => nil, "COLORTERM" => nil}) do
          expect(Termify.terminal.color_supported?).to be_true
        end
      end
    end
  end

  describe ".truecolor_supported?" do
    context "when COLORTERM=truecolor" do
      it "returns true" do
        with_env({"COLORTERM" => "truecolor"}) do
          expect(Termify.terminal.truecolor_supported?).to be_true
        end
      end
    end

    context "when COLORTERM=24bit" do
      it "returns true" do
        with_env({"COLORTERM" => "24bit"}) do
          expect(Termify.terminal.truecolor_supported?).to be_true
        end
      end
    end

    context "when COLORTERM is absent" do
      it "returns false" do
        with_env({"COLORTERM" => nil}) do
          expect(Termify.terminal.truecolor_supported?).to be_false
        end
      end
    end

    context "when color is not supported (NO_COLOR set)" do
      it "returns false even if COLORTERM is set" do
        with_env({"NO_COLOR" => "", "COLORTERM" => "truecolor"}) do
          expect(Termify.terminal.truecolor_supported?).to be_false
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
