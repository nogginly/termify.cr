require "../../../spec_helper"

Spectator.describe Termify::Markdown::BlockquoteIO do
  include Termify
  include Termify::Markdown

  def wrap(prefix : String, suffix : String = "") : {BlockquoteIO, IO::Memory}
    io = IO::Memory.new
    bio = BlockquoteIO.new(io, prefix, suffix)
    {bio, io}
  end

  # -- prefix injection -------------------------------------------------------

  describe "prefix injection" do
    it "prepends the prefix at the start of the first line" do
      bio, io = wrap("| ")
      bio << "hello\n"
      expect(io.to_s).to eq("| hello\n")
    end

    it "prepends the prefix on every line" do
      bio, io = wrap("| ")
      bio << "line one\nline two\n"
      expect(io.to_s).to eq("| line one\n| line two\n")
    end

    it "prepends the prefix on blank lines too" do
      bio, io = wrap("| ")
      bio << "line one\n\nline two\n"
      expect(io.to_s).to eq("| line one\n| \n| line two\n")
    end

    it "works with an empty prefix string" do
      bio, io = wrap("")
      bio << "text\n"
      expect(io.to_s).to eq("text\n")
    end

    it "works with ANSI sequences in the prefix" do
      bio, io = wrap("\e[2m| \e[0m")
      bio << "text\n"
      expect(io.to_s).to start_with("\e[2m| \e[0m")
      expect(io.to_s).to contain("text")
    end
  end

  # -- suffix injection -------------------------------------------------------

  describe "suffix injection" do
    it "appends the suffix before each newline" do
      bio, io = wrap("| ", "!")
      bio << "hello\n"
      expect(io.to_s).to eq("| hello!\n")
    end

    it "appends the suffix before every newline" do
      bio, io = wrap("| ", "!")
      bio << "line one\nline two\n"
      expect(io.to_s).to eq("| line one!\n| line two!\n")
    end

    it "appends the suffix on blank lines too" do
      bio, io = wrap("| ", "!")
      bio << "a\n\nb\n"
      expect(io.to_s).to eq("| a!\n| !\n| b!\n")
    end

    it "emits no suffix when suffix is empty" do
      bio, io = wrap("| ", "")
      bio << "text\n"
      expect(io.to_s).to eq("| text\n")
    end

    it "places suffix before newline, not after" do
      bio, io = wrap("", "END")
      bio << "text\n"
      suffix_pos = io.to_s.index("END")
      newline_pos = io.to_s.index('\n')
      expect(suffix_pos).to_not be_nil
      expect(newline_pos).to_not be_nil
      if s = suffix_pos
        if n = newline_pos
          expect(s).to be < n
        end
      end
    end

    it "emits ERASE_LINE + RESET suffix correctly" do
      suffix = ANSI::ERASE_LINE + ANSI::RESET
      bio, io = wrap("\e[48;5;233m│ ", suffix)
      bio << "text\n"
      output = io.to_s
      expect(output).to contain(ANSI::ERASE_LINE)
      expect(output).to contain(ANSI::RESET)
      erase_pos = output.index(ANSI::ERASE_LINE)
      reset_pos = output.index(ANSI::RESET)
      newline_pos = output.index('\n')
      if e = erase_pos
        if r = reset_pos
          if n = newline_pos
            expect(e).to be < n
            expect(r).to be < n
          end
        end
      end
    end
  end

  # -- write called with partial lines ----------------------------------------

  describe "partial writes" do
    it "handles content written in multiple write calls across a line boundary" do
      bio, io = wrap("| ")
      bio << "hel"
      bio << "lo\n"
      expect(io.to_s).to eq("| hello\n")
    end

    it "handles the prefix written on a subsequent write after a newline" do
      bio, io = wrap("| ")
      bio << "first\n"
      bio << "second\n"
      expect(io.to_s).to eq("| first\n| second\n")
    end
  end

  # -- read raises -------------------------------------------------------------

  describe "#read" do
    it "raises IO::Error" do
      bio, _ = wrap("| ")
      buf = Bytes.new(4)
      expect_raises(IO::Error) { bio.read(buf) }
    end
  end
end
