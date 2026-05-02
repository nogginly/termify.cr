require "../../../spec_helper"

Spectator.describe Termify::Markdown::Renderer do
  include Termify
  include Termify::Markdown

  def render_line(text : String) : String
    io = IO::Memory.new
    r = Renderer.new(io)
    r.feed(text + "\n")
    r.close
    io.to_s
  end

  def render_block(text : String) : String
    io = IO::Memory.new
    r = Renderer.new(io)
    r.feed(text)
    r.close
    io.to_s
  end

  # -------------------------------------------------------------------------
  # List item dispatch (block processing routes these correctly)
  # -------------------------------------------------------------------------
  describe "list items" do
    it "emits '* ' prefix for unordered '-' items" do
      output = render_line("- item")
      expect(output).to contain("* ")
      expect(output).to contain("item")
    end

    it "emits '* ' prefix for unordered '*' items" do
      output = render_line("* item")
      expect(output).to contain("* ")
      expect(output).to contain("item")
    end

    it "emits '* ' prefix for unordered '+' items" do
      output = render_line("+ item")
      expect(output).to contain("* ")
      expect(output).to contain("item")
    end

    it "emits '1. ' prefix for ordered items" do
      output = render_line("1. item")
      expect(output).to contain("1. ")
      expect(output).to contain("item")
    end
  end

  # -------------------------------------------------------------------------
  # Headings
  # -------------------------------------------------------------------------
  describe "headings" do
    it "applies bold + underline + bright-white fg for H1" do
      output = render_line("# Heading")
      expect(output).to contain(ANSI::BOLD)
      expect(output).to contain(ANSI::UNDERLINE)
      expect(output).to contain("\e[97m")
      expect(output).to contain("Heading")
    end

    it "applies bold + bright-white fg for H2" do
      output = render_line("## Heading")
      expect(output).to contain(ANSI::BOLD)
      expect(output).to contain("\e[97m")
      expect(output).to contain("Heading")
    end

    it "applies bold + white fg for H3" do
      output = render_line("### Heading")
      expect(output).to contain(ANSI::BOLD)
      expect(output).to contain("\e[37m")
      expect(output).to contain("Heading")
    end

    it "applies bold + dim for H4" do
      output = render_line("#### Heading")
      expect(output).to contain(ANSI::BOLD)
      expect(output).to contain(ANSI::DIM)
      expect(output).to contain("Heading")
    end

    it "applies italic + dim for H5" do
      output = render_line("##### Heading")
      expect(output).to contain(ANSI::ITALIC)
      expect(output).to contain(ANSI::DIM)
      expect(output).to contain("Heading")
    end

    it "applies dim for H6" do
      output = render_line("###### Heading")
      expect(output).to contain(ANSI::DIM)
      expect(output).to contain("Heading")
    end

    it "emits RESET after each heading" do
      output = render_line("# Heading")
      expect(output).to contain(ANSI::RESET)
    end

    it "strips the '#' markers from the output text" do
      output = render_line("## Hello")
      expect(output).to_not contain("##")
      expect(output).to contain("Hello")
    end
  end

  # -------------------------------------------------------------------------
  # Blockquote
  # -------------------------------------------------------------------------
  describe "blockquote" do
    it "emits the '| ' prefix" do
      output = render_line("> quote text")
      expect(output).to contain("| ")
      expect(output).to contain("quote text")
    end

    it "handles '>' without a trailing space" do
      output = render_line(">no space")
      expect(output).to contain("| ")
      expect(output).to contain("no space")
    end

    it "renders consecutive blockquote lines as a single block" do
      output = render_block("> line one\n> line two\n")
      expect(output).to contain("line one")
      expect(output).to contain("line two")
    end

    it "two blockquotes separated by a blank line both render" do
      output = render_block("> first\n\n> second\n")
      expect(output).to contain("first")
      expect(output).to contain("second")
    end
  end

  # -------------------------------------------------------------------------
  # Code fence
  # -------------------------------------------------------------------------
  describe "code fence" do
    it "emits code-block styling for lines inside a triple-backtick fence" do
      output = render_block("```\nsome code\n```\n")
      expect(output).to contain("some code")
      expect(output).to contain("\e[97m")
    end

    it "does not apply inline parsing inside a code fence" do
      output = render_block("```\n**not bold**\n```\n")
      expect(output).to contain("**not bold**")
    end

    it "supports tilde fences" do
      output = render_block("~~~\nsome code\n~~~\n")
      expect(output).to contain("some code")
      expect(output).to contain("\e[97m")
    end

    it "returns to normal mode after the closing fence marker" do
      output = render_block("```\ncode\n```\nnormal\n")
      expect(output).to contain("normal")
    end

    it "recognises a fence with 1 leading space" do
      output = render_block(" ```\nsome code\n ```\n")
      expect(output).to contain("some code")
      expect(output).to contain("\e[97m")
    end

    it "recognises a fence with 3 leading spaces" do
      output = render_block("   ```\nsome code\n   ```\n")
      expect(output).to contain("some code")
      expect(output).to contain("\e[97m")
    end

    it "does not recognise a fence with 4 or more leading spaces" do
      output = render_block("    ```\nsome code\n    ```\n")
      # 4-space indent is not a fence -- falls through to paragraph
      expect(output).to_not contain("\e[97m")
    end

    it "ignores the language tag on the opening fence line" do
      output = render_block("```crystal\nsome code\n```\n")
      expect(output).to contain("some code")
      expect(output).to_not contain("crystal")
    end
  end

  # -------------------------------------------------------------------------
  # Horizontal rule
  # -------------------------------------------------------------------------
  describe "horizontal rule" do
    it "recognises '---'" do
      output = render_line("---")
      expect(output).to contain(ANSI::DIM)
    end

    it "recognises '***'" do
      output = render_line("***")
      expect(output).to contain(ANSI::DIM)
    end

    it "recognises '___'" do
      output = render_line("___")
      expect(output).to contain(ANSI::DIM)
    end
  end

  # -------------------------------------------------------------------------
  # Block HTML
  # -------------------------------------------------------------------------
  describe "block HTML" do
    it "recognises a standalone opening tag" do
      output = render_line("<div>")
      expect(output).to contain("<div>")
      expect(output).to contain("\e[31m")
    end

    it "recognises a standalone closing tag" do
      output = render_line("</div>")
      expect(output).to contain("</div>")
      expect(output).to contain("\e[31m")
    end

    it "recognises a self-closing tag" do
      output = render_line("<hr/>")
      expect(output).to contain("<hr/>")
      expect(output).to contain("\e[31m")
    end

    it "recognises a tag with attributes" do
      output = render_line("<script src=\"app.js\">")
      expect(output).to contain("<script src=\"app.js\">")
      expect(output).to contain("\e[31m")
    end

    it "strips leading whitespace from the tag" do
      output = render_line("  <div>")
      expect(output).to contain("<div>")
      expect(output).to_not contain("  <div>")
    end

    it "does not apply inline parsing to the tag content" do
      output = render_line("<div class=\"**bold**\">")
      expect(output).to contain("**bold**")
      expect(output).to_not contain(ANSI::BOLD)
    end

    it "does not treat a multi-tag line as block HTML" do
      output = render_line("<div><span>")
      # falls through to paragraph + inline HTML scanning
      expect(output).to contain("\e[31m") # inline tags still styled
      expect(output).to contain("<div>")
      expect(output).to contain("<span>")
    end

    it "does not treat a line with text after the tag as block HTML" do
      output = render_line("<div> some text")
      expect(output).to contain("<div>")
      expect(output).to contain("some text")
    end

    it "emits RESET after the tag" do
      output = render_line("<div>")
      red_pos = output.index("\e[31m").not_nil!
      reset_pos = output.rindex(ANSI::RESET).not_nil!
      expect(red_pos).to be < reset_pos
    end
  end

  # -------------------------------------------------------------------------
  # Paragraph
  # -------------------------------------------------------------------------
  describe "paragraph" do
    it "passes plain text through with a trailing newline" do
      output = render_line("plain text here")
      expect(output).to contain("plain text here")
      expect(output.ends_with?('\n')).to be_true
    end

    it "does not apply bold or italic ANSI for plain paragraphs" do
      output = render_line("plain text here")
      expect(output).to_not contain(ANSI::BOLD)
      expect(output).to_not contain(ANSI::ITALIC)
    end
  end

  # -------------------------------------------------------------------------
  # Blank lines and block boundary behaviour
  # -------------------------------------------------------------------------
  describe "blank lines" do
    it "emits a bare newline for an empty line" do
      output = render_block("\n")
      expect(output).to eq("\n")
    end

    it "multiple consecutive blank lines do not produce more than one blank line of output each" do
      output = render_block("para one\n\n\n\npara two\n")
      expect(output).to contain("para one")
      expect(output).to contain("para two")
      expect(output).to_not contain("\n\n\n\n\n")
    end

    it "a blank line between paragraphs produces a single blank output line" do
      output = render_block("first\n\nsecond\n")
      idx_first = output.index("first").not_nil!
      idx_second = output.index("second").not_nil!
      between = output[idx_first + "first".size...idx_second]
      expect(between).to eq("\n\n")
    end
  end

  # -------------------------------------------------------------------------
  # newline_before / newline_after block boundary collapsing
  # -------------------------------------------------------------------------
  describe "newline_before and newline_after" do
    it "emits one blank line between two blocks when outgoing has newline_after" do
      sheet = Stylesheet.new
      sheet[BlockElement::H1] = BlockStyle.new(bold: true, newline_after: true)
      sheet[BlockElement::Paragraph] = BlockStyle.new
      output = String.build do |io|
        r = Renderer.new(io, sheet)
        r << "# Heading\nParagraph text\n"
        r.close
      end
      expect(output).to contain("\n\nParagraph")
      expect(output).not_to contain("\n\n\nParagraph")
    end

    it "emits one blank line between two blocks when incoming has newline_before" do
      sheet = Stylesheet.new
      sheet[BlockElement::H1] = BlockStyle.new(bold: true)
      sheet[BlockElement::Paragraph] = BlockStyle.new(newline_before: true)
      output = String.build do |io|
        r = Renderer.new(io, sheet)
        r << "# Heading\nParagraph text\n"
        r.close
      end
      expect(output).to contain("\n\nParagraph")
      expect(output).not_to contain("\n\n\nParagraph")
    end

    it "emits only one blank line when both newline_after and newline_before are set" do
      sheet = Stylesheet.new
      sheet[BlockElement::H1] = BlockStyle.new(bold: true, newline_after: true)
      sheet[BlockElement::Paragraph] = BlockStyle.new(newline_before: true)
      output = String.build do |io|
        r = Renderer.new(io, sheet)
        r << "# Heading\nParagraph text\n"
        r.close
      end
      expect(output).to contain("\n\nParagraph")
      expect(output).not_to contain("\n\n\nParagraph")
    end

    it "does not accumulate blank lines between same-type blocks separated by a blank line" do
      sheet = Stylesheet.new
      sheet[BlockElement::Blockquote] = BlockStyle.new(newline_before: true, newline_after: true)
      output = String.build do |io|
        r = Renderer.new(io, sheet)
        r << "> Note\n\n> Warning\n"
        r.close
      end
      expect(output).not_to contain("\n\n\n")
    end

    it "emits a trailing blank line when the last block has newline_after" do
      sheet = Stylesheet.new
      sheet[BlockElement::Paragraph] = BlockStyle.new(newline_after: true)
      output = String.build do |io|
        r = Renderer.new(io, sheet)
        r << "final paragraph\n"
        r.close
      end
      expect(output.ends_with?("\n\n")).to be_true
    end
  end
end
