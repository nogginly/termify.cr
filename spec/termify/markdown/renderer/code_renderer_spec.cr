require "../../../spec_helper"

Spectator.describe Termify::Markdown::CodeRenderer do
  include Termify
  include Termify::Markdown

  def make_renderer(language = "", style = CodeBlockStyle::NONE, indent = "") : {CodeRenderer, IO::Memory}
    io = IO::Memory.new
    cr = CodeRenderer.new(language, style, io, indent)
    {cr, io}
  end

  # -- language ---------------------------------------------------------------

  describe "#language" do
    it "stores the language tag" do
      cr, _ = make_renderer(language: "crystal")
      expect(cr.language).to eq("crystal")
    end

    it "stores an empty string when no language tag is given" do
      cr, _ = make_renderer(language: "")
      expect(cr.language).to eq("")
    end
  end

  # -- feed -------------------------------------------------------------------

  describe "#feed" do
    it "emits the line followed by a newline" do
      cr, io = make_renderer
      cr.feed("some code")
      expect(io.to_s).to eq("some code\n")
    end

    it "emits multiple lines in order" do
      cr, io = make_renderer
      cr.feed("line one")
      cr.feed("line two")
      expect(io.to_s).to eq("line one\nline two\n")
    end

    it "preserves leading whitespace in lines" do
      cr, io = make_renderer
      cr.feed("  indented")
      expect(io.to_s).to contain("  indented")
    end

    it "does not apply inline parsing -- markers are emitted verbatim" do
      cr, io = make_renderer
      cr.feed("**not bold**")
      expect(io.to_s).to contain("**not bold**")
    end

    it "applies the block style ANSI sequence" do
      style = CodeBlockStyle.new(bold: true)
      cr, io = make_renderer(style: style)
      cr.feed("styled")
      expect(io.to_s).to contain(ANSI::BOLD)
    end

    it "emits a reset after the line when a style is active" do
      style = CodeBlockStyle.new(bold: true)
      cr, io = make_renderer(style: style)
      cr.feed("styled")
      expect(io.to_s).to contain(ANSI::RESET)
    end

    it "emits no ANSI sequences when the style is NONE" do
      cr, io = make_renderer(style: CodeBlockStyle::NONE)
      cr.feed("plain")
      expect(io.to_s).to eq("plain\n")
    end

    it "prepends the line_prefix from the style" do
      style = CodeBlockStyle.new(line_prefix: "  ")
      cr, io = make_renderer(style: style)
      cr.feed("code")
      expect(io.to_s).to contain("  code")
    end

    it "prepends the indent string before the prefix" do
      style = CodeBlockStyle.new(line_prefix: "> ")
      cr, io = make_renderer(style: style, indent: "    ")
      cr.feed("code")
      expect(io.to_s).to contain("    > code")
    end

    it "prepends only the indent when style has no prefix" do
      cr, io = make_renderer(indent: "  ")
      cr.feed("code")
      expect(io.to_s).to contain("  code")
    end
  end

  # -- close ------------------------------------------------------------------

  describe "#close" do
    it "does not emit anything extra" do
      cr, io = make_renderer
      cr.feed("code")
      output_before = io.to_s
      cr.close
      expect(io.to_s).to eq(output_before)
    end
  end

  # -- line numbers -----------------------------------------------------------

  describe "line numbers" do
    it "emits no gutter when line_number_format is nil" do
      cr, io = make_renderer(style: CodeBlockStyle.new(line_number_format: nil))
      cr.feed("code")
      expect(io.to_s).to eq("code\n")
    end

    it "prepends the formatted line number on each line" do
      cr, io = make_renderer(style: CodeBlockStyle.new(line_number_format: "%2d | "))
      cr.feed("first")
      cr.feed("second")
      lines = io.to_s.lines
      expect(lines[0]).to eq(" 1 | first")
      expect(lines[1]).to eq(" 2 | second")
    end

    it "increments the line number for each feed call" do
      cr, io = make_renderer(style: CodeBlockStyle.new(line_number_format: "%d "))
      3.times { |i| cr.feed("line #{i + 1}") }
      expect(io.to_s).to contain("1 line 1")
      expect(io.to_s).to contain("2 line 2")
      expect(io.to_s).to contain("3 line 3")
    end

    it "places the gutter before the line_prefix" do
      style = CodeBlockStyle.new(line_number_format: "%d:", line_prefix: "  ")
      cr, io = make_renderer(style: style)
      cr.feed("code")
      expect(io.to_s).to contain("1:  code")
    end

    it "places the gutter after the indent" do
      cr, io = make_renderer(style: CodeBlockStyle.new(line_number_format: "%d "), indent: "  ")
      cr.feed("code")
      expect(io.to_s).to start_with("  1 code")
    end

    it "applies gutter_style ANSI around the gutter text" do
      gs = InlineStyle.new(dim: true)
      style = CodeBlockStyle.new(line_number_format: "%d ", gutter_style: gs)
      cr, io = make_renderer(style: style)
      cr.feed("code")
      output = io.to_s
      expect(output).to contain(ANSI::DIM)
      expect(output).to contain("1 ")
      expect(output).to contain("code")
    end

    it "resumes block style after gutter when gutter_style is set" do
      block_ansi = ANSI::BOLD
      gs = InlineStyle.new(dim: true)
      style = CodeBlockStyle.new(bold: true, line_number_format: "%d ", gutter_style: gs)
      cr, io = make_renderer(style: style)
      cr.feed("code")
      output = io.to_s
      # block style must appear before the code content
      bold_pos = output.index(ANSI::BOLD)
      code_pos = output.index("code")
      expect(bold_pos).to_not be_nil
      expect(code_pos).to_not be_nil
      if b = bold_pos
        if c = code_pos
          expect(b).to be < c
        end
      end
    end

    it "emits no extra sequences when gutter_style is nil" do
      style = CodeBlockStyle.new(line_number_format: "%d ")
      cr, io = make_renderer(style: style)
      cr.feed("code")
      expect(io.to_s).to eq("1 code\n")
    end
  end

  # -- background erase to EOL ------------------------------------------------

  describe "background color erase to EOL" do
    it "emits ERASE_LINE before RESET when style has a bg color" do
      style = CodeBlockStyle.new(bg: Colorize::ColorANSI::DarkGray)
      cr, io = make_renderer(style: style)
      cr.feed("code")
      expect(io.to_s).to contain(ANSI::ERASE_LINE)
    end

    it "does not emit ERASE_LINE when style has no bg color" do
      cr, io = make_renderer
      cr.feed("code")
      expect(io.to_s).to_not contain(ANSI::ERASE_LINE)
    end
  end

  # -- highlighting -----------------------------------------------------------

  describe "highlighting" do
    it "falls back to plain output for an unknown language" do
      style = CodeBlockStyle.new(highlight_theme: "default-dark")
      cr, io = make_renderer(language: "not_a_real_language", style: style)
      cr.feed("some code")
      cr.close
      expect(io.to_s.gsub(/\e\[[0-9;]*m/, "")).to contain("some code")
    end

    it "falls back to plain output for an unknown theme" do
      style = CodeBlockStyle.new(highlight_theme: "not_a_real_theme")
      cr, io = make_renderer(language: "javascript", style: style)
      cr.feed("some code")
      cr.close
      expect(io.to_s.gsub(/\e\[[0-9;]*m/, "")).to contain("some code")
    end

    it "falls back to plain output when language is empty even if theme is set" do
      style = CodeBlockStyle.new(highlight_theme: "default-dark")
      cr, io = make_renderer(language: "", style: style)
      cr.feed("var x = 1;")
      cr.close
      expect(io.to_s.gsub(/\e\[[0-9;]*m/, "")).to contain("var x = 1;")
    end

    it "emits ANSI sequences when highlighting a known language and theme" do
      style = CodeBlockStyle.new(highlight_theme: "default-dark")
      cr, io = make_renderer(language: "javascript", style: style)
      cr.feed("var x = 1;")
      cr.close
      expect(io.to_s).to contain("\e[")
    end

    it "preserves multi-line comment state across feed calls" do
      style = CodeBlockStyle.new(highlight_theme: "default-dark")
      cr, io = make_renderer(language: "javascript", style: style)
      cr.feed("/* start of comment")
      cr.feed("   end of comment */")
      cr.close
      plain = io.to_s.gsub(/\e\[[0-9;]*m/, "")
      expect(plain).to contain("start of comment")
      expect(plain).to contain("end of comment")
      io.to_s.lines.each do |line|
        expect(line).to contain("\e[") unless line.strip.empty?
      end
    end

    it "resets tokenizer state on close" do
      style = CodeBlockStyle.new(highlight_theme: "default-dark")
      cr, io = make_renderer(language: "javascript", style: style)
      cr.feed("/* open comment")
      cr.close
      plain = io.to_s.gsub(/\e\[[0-9;]*m/, "")
      expect(plain).to contain("open comment")
    end
  end
end
