require "../spec_helper"

# A terminal whose ends are in memory but which answers queries anyway.
private class ScriptedTerminal < Termify::Terminal
  def interactive? : Bool
    true
  end
end

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

  describe "#interactive?" do
    it "is false when the ends are not a terminal" do
      term = Termify::Terminal.new(IO::Memory.new, IO::Memory.new)
      expect(term.interactive?).to be_false
    end
  end

  describe "#cursor_row" do
    context "when the ends are not a terminal" do
      it "returns the default row without asking" do
        written = IO::Memory.new
        term = Termify::Terminal.new(IO::Memory.new("\e[12;1R"), written)

        expect(term.cursor_row).to eq(Termify::Terminal::DEFAULT_CURSOR_ROW)
        expect(written.to_s).to be_empty
      end
    end

    context "when the terminal answers" do
      it "writes the query and reports the row" do
        written = IO::Memory.new
        term = ScriptedTerminal.new(IO::Memory.new("\e[12;40R"), written)

        expect(term.cursor_row).to eq(12)
        expect(written.to_s).to eq("\e[6n")
      end

      it "reports a row of more than one digit" do
        term = ScriptedTerminal.new(IO::Memory.new("\e[137;2R"), IO::Memory.new)
        expect(term.cursor_row).to eq(137)
      end
    end

    context "when the terminal answers badly" do
      it "returns the default row for a reply with no row field" do
        term = ScriptedTerminal.new(IO::Memory.new("\e[R"), IO::Memory.new)
        expect(term.cursor_row).to eq(Termify::Terminal::DEFAULT_CURSOR_ROW)
      end

      it "returns the default row when the input ends first" do
        term = ScriptedTerminal.new(IO::Memory.new(""), IO::Memory.new)
        expect(term.cursor_row).to eq(Termify::Terminal::DEFAULT_CURSOR_ROW)
      end

      it "stops reading at the limit rather than consuming everything" do
        input = IO::Memory.new("x" * 100 + "\e[12;1R")
        term = ScriptedTerminal.new(input, IO::Memory.new)

        expect(term.cursor_row).to eq(Termify::Terminal::DEFAULT_CURSOR_ROW)
        expect(input.pos).to eq(32)
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
