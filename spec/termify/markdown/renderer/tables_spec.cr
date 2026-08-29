require "../../../spec_helper"

Spectator.describe Termify::Markdown::Renderer do
  include Termify
  include Termify::Markdown

  def render_block(text : String) : String
    io = IO::Memory.new
    r = Renderer.new(io)
    r.feed(text)
    r.close
    io.to_s
  end

  describe "tables" do
    it "renders cell content" do
      output = render_block("Name | Age\n-----|----\nAlice | 30\n")
      expect(output).to contain("Name")
      expect(output).to contain("Age")
      expect(output).to contain("Alice")
      expect(output).to contain("30")
    end

    it "supports leading pipe syntax" do
      output = render_block("| X | Y |\n|---|---|\n| a | b |\n")
      expect(output).to contain("X")
      expect(output).to contain("Y")
      expect(output).to contain("a")
      expect(output).to contain("b")
    end

    # Inline styling does not survive a table cell: TableRenderer strips escape
    # sequences before handing text to tablo, which would otherwise count them
    # as visible width. The markup is still consumed, so the delimiters do not
    # leak into the output. See SCOPE.md.
    #
    # Asserted against the body line alone. Table borders and header cells are
    # styled unconditionally via ANSI, so the surrounding output legitimately
    # carries escapes.
    it "styles inline markup inside a cell" do
      output = render_block("Header | Other\n-------|------\n**bold cell** | plain\n")
      body = output.lines.select(&.includes?("bold cell")).join
      expect(body).not_to be_empty
      expect(body).not_to contain("**")
      expect(body).to contain(ANSI::BOLD)
    end

    it "styles only the marked span, not the whole cell" do
      output = render_block("H | H2\n--|--\nkeep **bold** here | x\n")
      body = output.lines.select(&.includes?("bold")).join
      # The bold sequence must sit immediately before the styled word, so an
      # off-by-one in the wrapped-line cursor shows up here.
      expect(body).to contain("#{ANSI::BOLD}bold")
      expect(body).not_to contain("#{ANSI::BOLD}keep")
    end

    it "resolves inline markup in a header cell" do
      output = render_block("**Head** | Other\n--------|------\n1 | 2\n")
      expect(output).not_to contain("**")
      expect(output).to contain("Head")
    end

    it "consumes code spans and links in cells" do
      output = render_block("A | B\n--|--\n`code` | [text](https://example.com)\n")
      expect(output).to contain("code")
      expect(output).to contain("text")
      expect(output).not_to contain("example.com")
      expect(output).not_to contain("`")
    end

    it "styles a span that survives wrapping in a narrow column" do
      wide = (["word"] * 40).join(" ")
      output = render_block("A | B\n--|--\n**#{wide}** | x\n")
      expect(output).to contain(ANSI::BOLD)
      expect(output).not_to contain("**")
    end

    it "terminates on a non-table line and renders what follows normally" do
      output = render_block("A | B\n--|--\n1 | 2\n\nfollowing paragraph\n")
      expect(output).to contain("following paragraph")
    end

    it "styles borders and headers regardless of tty" do
      # Specs run with stdout piped. Table styling must not depend on that.
      output = render_block("Header | Other\n-------|------\n1 | 2\n")
      expect(output).to contain(ANSI::BOLD)
      expect(output).to contain(ANSI::RESET)
    end

    it "flushes the table when a blockquote follows immediately" do
      output = render_block("A | B\n--|--\n1 | 2\n> quoted\n")
      expect(output).to contain("1")
      expect(output).to contain("2")
      expect(output).to contain("quoted")
    end

    it "flushes the table when a heading follows immediately" do
      output = render_block("A | B\n--|--\n1 | 2\n# Heading\n")
      expect(output).to contain("1")
      expect(output).to contain("Heading")
    end

    it "does not disturb blank line accounting around a table" do
      output = render_block("before\n\nA | B\n--|--\n1 | 2\n\nafter\n")
      expect(output).to contain("before")
      expect(output).to contain("after")
      expect(output).not_to contain("\n\n\n")
    end

    it "renders a table inside a list continuation" do
      output = render_block("1. item\n\n   A | B\n   --|--\n   1 | 2\n")
      expect(output).to contain("item")
      expect(output).to contain("A")
      expect(output).to contain("1")
    end

    it "indents a table inside a nested list item" do
      output = render_block("- outer\n  - inner\n\n    A | B\n    --|--\n    1 | 2\n")
      expect(output).to contain("A")
      expect(output).to contain("1")
      table_line = output.split('\n').find { |l| l.includes?("A") && l.includes?("B") }
      expect(table_line).not_to be_nil
      expect(table_line.not_nil!.starts_with?(" ")).to be_true
    end

    it "does not treat a paragraph containing a pipe as a table" do
      output = render_block("use a | b to choose\n\nnext paragraph\n")
      expect(output).to contain("use a | b to choose")
      expect(output).to contain("next paragraph")
    end

    it "does not treat a logical-or in prose as a table" do
      output = render_block("Write `if x || y` to test either.\n")
      expect(output).to contain("if x || y")
    end

    it "renders a heading containing a pipe as a heading" do
      output = render_block("# Title | Subtitle\n")
      expect(output).to contain("Title | Subtitle")
      expect(output).to contain(ANSI::BOLD)
    end

    it "releases an unconfirmed row when the next line is not a delimiter" do
      output = render_block("a | b\nnot a delimiter\n")
      expect(output).to contain("a | b")
      expect(output).to contain("not a delimiter")
    end

    it "releases an unconfirmed row at end of input" do
      output = render_block("a | b\n")
      expect(output).to contain("a | b")
    end

    it "starts a table when the delimiter follows a released row" do
      output = render_block("prose | with pipe\nName | Age\n-----|----\nAlice | 30\n")
      expect(output).to contain("prose | with pipe")
      expect(output).to contain("Alice")
      expect(output).to contain("30")
    end

    it "treats a bare dashed line as a horizontal rule, not a delimiter" do
      output = render_block("paragraph\n\n-----\n\nmore\n")
      expect(output).to contain("-----")
      expect(output).to contain("more")
    end

    it "accepts alignment colons in the delimiter row" do
      output = render_block("| L | C | R |\n|:--|:-:|--:|\n| a | b | c |\n")
      expect(output).to contain("a")
      expect(output).to contain("c")
    end

    it "does not treat a pipe followed by a blank line as a table" do
      output = render_block("a | b\n\nparagraph\n")
      expect(output).to contain("a | b")
      expect(output).to contain("paragraph")
    end

    it "doesn't fail when more data columns than headers" do
      input = "|Heading1|\n|-------:|---|\n|    row1|  Lorem ipsum dolor sit amet|"
      expect { render_block(input) }.not_to raise_error(IndexError)
    end

    it "doesn't fail when more data columns than headers, v2" do
      input = "|Heading1|\n|-------|\n|    row1|  Lorem ipsum dolor sit amet|"
      expect { render_block(input) }.not_to raise_error(IndexError)
    end
  end
end
