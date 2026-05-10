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

    it "renders inline markup inside a cell" do
      output = render_block("Header\n------\n**bold cell**\n")
      expect(output).to contain("bold cell")
      expect(output).to contain(ANSI::BOLD)
    end

    it "terminates on a non-table line and renders what follows normally" do
      output = render_block("A | B\n--|--\n1 | 2\n\nfollowing paragraph\n")
      expect(output).to contain("following paragraph")
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
