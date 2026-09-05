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

  describe "lists" do
    describe "unordered list" do
      it "renders a single item" do
        output = render_line("- item")
        expect(output).to contain("item")
        expect(output).to contain("* ")
      end

      it "recognises -, * and + markers" do
        ["- item", "* item", "+ item"].each do |line|
          expect(render_line(line)).to contain("item")
        end
      end

      it "renders inline markup inside an item" do
        output = render_line("- **bold** item")
        expect(output).to contain(ANSI::BOLD)
        expect(output).to contain("bold")
      end

      it "uses different bullet characters at depth 1 vs depth 2" do
        output = render_block("- level 1\n  - level 2\n")
        lines = output.split('\n').reject(&.empty?)
        expect(lines[0]).to contain("* ")
        expect(lines[1]).to_not contain("* ") # second bullet character
      end

      it "indents depth-2 items more than depth-1 items" do
        output = render_block("- level 1\n  - level 2\n")
        lines = output.split('\n').reject(&.empty?)
        depth1_indent = lines[0].index(/\S/).not_nil!
        depth2_indent = lines[1].index(/\S/).not_nil!
        expect(depth2_indent).to be > depth1_indent
      end

      it "returns to depth-1 prefix after a depth-2 item" do
        output = render_block("- l1\n  - l2\n- l1 again\n")
        lines = output.split('\n').reject(&.empty?)
        expect(lines[0].index(/\S/)).to eq(lines[2].index(/\S/))
      end

      it "renders three levels of nesting" do
        output = render_block("- l1\n  - l2\n    - l3\n")
        lines = output.split('\n').reject(&.empty?)
        d1 = lines[0].index(/\S/).not_nil!
        d2 = lines[1].index(/\S/).not_nil!
        d3 = lines[2].index(/\S/).not_nil!
        expect(d1).to be < d2
        expect(d2).to be < d3
      end
    end

    describe "ordered list" do
      it "renders a single item with '1. ' prefix" do
        output = render_line("1. item")
        expect(output).to contain("item")
        expect(output).to contain("1. ")
      end

      it "increments the counter for successive items" do
        output = render_block("1. first\n2. second\n3. third\n")
        expect(output).to contain("1. ")
        expect(output).to contain("2. ")
        expect(output).to contain("3. ")
      end

      it "renders inline markup inside an ordered item" do
        output = render_line("1. **bold** item")
        expect(output).to contain(ANSI::BOLD)
        expect(output).to contain("bold")
      end

      it "resets counter at a fresh nested ordered level" do
        output = render_block("1. outer\n   1. inner\n")
        lines = output.split('\n').reject(&.empty?)
        expect(lines[0]).to contain("1. ")
        expect(lines[1]).to contain("1. ")
      end

      it "resumes outer counter after returning from nested" do
        output = render_block("1. a\n2. b\n   1. nested\n3. c\n")
        expect(output).to contain("3. ")
      end

      it "starts at the number written on the first item" do
        output = render_block("3. Three\n4. Four\n")
        lines = output.split('\n').reject(&.empty?)
        expect(lines[0]).to contain("3. ")
        expect(lines[0]).to contain("Three")
        expect(lines[1]).to contain("4. ")
        expect(lines[1]).to contain("Four")
      end

      it "counts on from the start number regardless of later numbers" do
        output = render_block("5. five\n9. six\n1. seven\n")
        lines = output.split('\n').reject(&.empty?)
        expect(lines[0]).to contain("5. ")
        expect(lines[1]).to contain("6. ")
        expect(lines[2]).to contain("7. ")
      end

      it "seeds a nested level from its own first number" do
        output = render_block("3. outer\n   7. inner\n   8. inner two\n")
        lines = output.split('\n').reject(&.empty?)
        expect(lines[0]).to contain("3. ")
        expect(lines[1]).to contain("7. ")
        expect(lines[2]).to contain("8. ")
      end

      it "resumes the outer counter after a differently numbered nested level" do
        output = render_block("3. outer\n   7. inner\n4. outer two\n")
        lines = output.split('\n').reject(&.empty?)
        expect(lines[2]).to contain("4. ")
      end

      it "starts a new list from its own number after an unordered list" do
        output = render_block("- bullet\n3. Three\n")
        lines = output.split('\n').reject(&.empty?)
        expect(lines[0]).to contain("* ")
        expect(lines[1]).to contain("3. ")
      end

      it "renders a zero-numbered first item as zero" do
        output = render_block("0. zero\n1. one\n")
        lines = output.split('\n').reject(&.empty?)
        expect(lines[0]).to contain("0. ")
        expect(lines[1]).to contain("1. ")
      end

      it "accepts a close paren as the delimiter" do
        output = render_block("1) one\n2) two\n")
        lines = output.split('\n').reject(&.empty?)
        expect(lines[0]).to contain("one")
        expect(lines[1]).to contain("two")
      end

      it "renders a close paren delimiter as a full stop" do
        output = render_block("3) Three\n")
        lines = output.split('\n').reject(&.empty?)
        expect(lines[0]).to contain("3. ")
        expect(lines[0]).not_to contain("3) ")
      end

      it "treats the two delimiters as one list" do
        output = render_block("1. one\n2) two\n3. three\n")
        lines = output.split('\n').reject(&.empty?)
        expect(lines[1]).to contain("2. ")
        expect(lines[2]).to contain("3. ")
      end

      it "seeds from a close paren first item" do
        output = render_block("7) seven\n8) eight\n")
        lines = output.split('\n').reject(&.empty?)
        expect(lines[0]).to contain("7. ")
        expect(lines[1]).to contain("8. ")
      end

      it "does not treat a paren without a digit as a list" do
        output = render_block("a) not a list\n")
        expect(output).to contain("a) not a list")
      end

      it "does not treat a bare number and paren mid-line as a list" do
        output = render_block("See item 2) for details.\n")
        expect(output).to contain("See item 2) for details.")
      end
    end

    describe "bullet glyphs" do
      it "uses a distinct glyph at each of the three depths" do
        output = render_block("- one\n  - two\n    - three\n")
        lines = output.split('\n').reject(&.empty?)
        expect(lines[0]).to contain("* ")
        expect(lines[1]).to contain("+ ")
        expect(lines[2]).to contain("- ")
      end

      it "cycles back to the first glyph at the fourth depth" do
        output = render_block("- one\n  - two\n    - three\n      - four\n")
        lines = output.split('\n').reject(&.empty?)
        expect(lines[3]).to contain("* ")
      end

      it "renders every source marker with the same glyph" do
        ["-", "*", "+"].each do |marker|
          output = render_block("#{marker} item\n")
          expect(output).to contain("* item")
        end
      end

      it "treats a change of source marker as one continuing list" do
        output = render_block("- one\n* two\n+ three\n")
        lines = output.split('\n').reject(&.empty?)
        expect(lines.size).to eq(3)
        lines.each { |line| expect(line).to contain("* ") }
      end

      it "uses only ASCII glyphs" do
        output = render_block("- one\n  - two\n    - three\n")
        expect(output.each_char.all?(&.ascii?)).to be_true
      end
    end

    describe "mixed ordered and unordered" do
      it "renders an ordered list nested inside an unordered list" do
        output = render_block("- item\n  1. ordered nested\n")
        expect(output).to contain("* ")
        expect(output).to contain("1. ")
      end

      it "renders an unordered list nested inside an ordered list" do
        output = render_block("1. item\n   - unordered nested\n")
        expect(output).to contain("1. ")
        expect(output).to contain("+ ") # depth-1 bullet (plus)
      end
    end

    describe "list termination" do
      it "terminates on a non-indented line after a blank" do
        output = render_block("- item\n\nfollowing\n")
        expect(output).to contain("item")
        expect(output).to contain("following")
      end

      it "emits a blank line before the non-list line that terminated the list" do
        output = render_block("- item\n\nfollowing\n")
        expect(output).to contain("\n\n")
      end

      it "terminates on a heading" do
        output = render_block("- item\n# Heading\n")
        expect(output).to contain("item")
        expect(output).to contain("Heading")
      end

      it "continues counter across a blank line (loose list)" do
        output = render_block("1. first\n\n1. second\n")
        expect(output).to contain("1. ")
        expect(output).to contain("2. ")
      end

      it "resets counter when a new list starts after the previous one exits" do
        output = render_block("1. first list\n\nnot a list\n\n1. new list\n")
        expect(output.scan("1. ").size).to eq(2)
      end
    end

    describe "continuation blocks" do
      it "renders an indented paragraph as part of the same list item" do
        output = render_block("1. First item\n\n   Continuation paragraph.\n")
        expect(output).to contain("First item")
        expect(output).to contain("Continuation paragraph.")
      end

      it "indents continuation paragraph to content column" do
        output = render_block("1. item\n\n   continuation\n")
        expect(output).to contain("   continuation")
      end

      it "indents continuation paragraph for unordered list to content column" do
        output = render_block("- item\n\n  continuation\n")
        expect(output).to contain("  continuation")
      end

      it "swallows blank lines within a list item (no blank emitted between item and continuation)" do
        output = render_block("1. item\n\n   continuation\n")
        lines = output.split('\n')
        item_idx = lines.index { |l| l.includes?("item") }.not_nil!
        cont_idx = lines.index { |l| l.includes?("continuation") }.not_nil!
        expect(cont_idx - item_idx).to eq(1)
      end

      it "renders a continuation after multiple blank lines" do
        output = render_block("1. item\n\n\n   continuation\n")
        expect(output).to contain("item")
        expect(output).to contain("continuation")
      end

      it "renders a continuation after multiple blank lines" do
        output = render_block("1. item\n\n\n   continuation\n")
        expect(output).to contain("item")
        expect(output).to contain("continuation")
      end

      it "accepts a 2-space indented paragraph as a continuation (shallower than content_indent)" do
        output = render_block("1. One\n  Paragraph in list item\n2. Two\n")
        expect(output).to contain("One")
        expect(output).to contain("Paragraph in list item")
        expect(output).to contain("2. ")
        # List must not restart at 1
        expect(output.scan("1. ").size).to eq(1)
      end

      it "accepts a 2-space indented code fence as a continuation" do
        output = render_block("1. Three\n  ```\n  Code block\n  ```\n2. Four\n")
        expect(output).to contain("Three")
        expect(output).to contain("Code block")
        expect(output).to_not contain("```")
        expect(output).to contain("2. ")
      end

      it "renders an indented code fence as part of the same list item" do
        output = render_block("1. item\n\n   ```\n   code here\n   ```\n")
        expect(output).to contain("item")
        expect(output).to contain("code here")
      end

      it "indents code fence body lines to content column" do
        output = render_block("1. item\n\n   ```\n   code here\n   ```\n")
        expect(output).to contain("   code here")
      end

      it "detects the closing fence and does not emit it as a code body line" do
        output = render_block("1. item\n\n   ```\n   code here\n   ```\n")
        expect(output).to_not contain("```")
      end

      it "renders a list item after a fenced code block continuation" do
        output = render_block("1. first\n\n   ```\n   code\n   ```\n\n2. second\n")
        expect(output).to contain("code")
        expect(output).to contain("2. ")
        expect(output).to_not contain("```")
      end

      it "renders a paragraph after a fenced code block continuation" do
        output = render_block("1. item\n\n   ```\n   code\n   ```\n\nfollowing paragraph\n")
        expect(output).to contain("code")
        expect(output).to contain("following paragraph")
        expect(output).to_not contain("```")
      end

      it "renders an indented table as part of the same list item" do
        output = render_block("1. item\n\n   A | B\n   --|--\n   1 | 2\n")
        expect(output).to contain("item")
        expect(output).to contain("A")
        expect(output).to contain("1")
      end

      it "resumes list numbering after a continuation block" do
        output = render_block("1. first\n\n   paragraph\n\n2. second\n")
        expect(output).to contain("1. ")
        expect(output).to contain("2. ")
      end

      it "renders a blockquote continuation inside a list item" do
        output = render_block("1. Three\n  > quoted\n2. Four\n")
        expect(output).to contain("Three")
        expect(output).to contain("quoted")
        expect(output).to contain("Four")
      end

      it "applies blockquote prefix decoration to content inside a list item" do
        sheet = Stylesheet.new({:blockquote => {line_prefix: "| "}},
          merge: Stylesheet.default)
        io = IO::Memory.new
        r = Renderer.new(io, sheet)
        r.feed("1. Three\n  > quoted\n2. Four\n")
        r.close
        output = io.to_s
        expect(output).to contain("| quoted")
        expect(output).to_not contain("| Three")
        expect(output).to_not contain("| Four")
      end

      it "indents the blockquote prefix after the list visual indent" do
        sheet = Stylesheet.new({:blockquote => {line_prefix: "| "}},
          merge: Stylesheet.default)
        io = IO::Memory.new
        r = Renderer.new(io, sheet)
        r.feed("1. Three\n  > quoted\n2. Four\n")
        r.close
        output = io.to_s
        # List visual indent (3 spaces for "1. ") must precede the blockquote prefix
        expect(output.lines.select { |l| l.includes?("quoted") }.first).to match(/^\s+\| quoted/)
      end

      it "renders a blockquote with its own nested list inside a list item" do
        md = "1. Three\n  > Block quote\n  >\n  > - With its own list\n  > - Of stuff\n2. Four\n"
        output = render_block(md)
        expect(output).to contain("Three")
        expect(output).to contain("Block quote")
        expect(output).to contain("With its own list")
        expect(output).to contain("Of stuff")
        expect(output).to contain("Four")
      end

      it "keeps nested list items inside the blockquote, not at the outer list level" do
        # In the broken state, "- With its own list" became an outer list item
        # causing the outer ordered list to count it, so "Four" would be "4." or later.
        md = "1. Three\n  > Block quote\n  >\n  > - With its own list\n  > - Of stuff\n2. Four\n"
        output = render_block(md)
        expect(output).to contain("2. ")
        # Outer list must not advance past 2 due to spurious items
        expect(output).to_not contain("3. ")
      end

      it "applies blockquote prefix to all lines including blank separators and nested list content" do
        sheet = Stylesheet.new({:blockquote => {line_prefix: "| "}},
          merge: Stylesheet.default)
        io = IO::Memory.new
        r = Renderer.new(io, sheet)
        r.feed("1. Three\n  > Block quote\n  >\n  > - item\n2. Four\n")
        r.close
        output = io.to_s
        expect(output).to contain("| Block quote")
        expect(output).to contain("| ")
        # The list item inside the blockquote must also carry the prefix
        expect(output.lines.select { |l| l.includes?("item") }.first).to contain("| ")
      end

      it "resumes the outer list after a blockquote continuation" do
        output = render_block("1. Three\n  > quoted\n2. Four\n")
        expect(output).to contain("2. ")
      end
    end

    describe "leaving a list" do
      # The blank line between a list and what follows is emitted by
      # handle_list_line. It must go through the same accounting as every
      # other blank, or open_block adds a second one behind it.
      def blank_runs(output : String) : Array(Int32)
        runs = [] of Int32
        count = 0
        output.split('\n').each do |line|
          if line.strip.empty?
            count += 1
          else
            runs << count if count > 0
            count = 0
          end
        end
        runs
      end

      it "separates a list from a following paragraph by one blank line" do
        output = render_block("- one\n- two\n\nAfter the list.\n")
        expect(output).to contain("After the list.")
        expect(blank_runs(output)).to all(be <= 1)
      end

      it "separates a list from a following heading by one blank line" do
        output = render_block("- one\n\n# Heading\n")
        expect(output).to contain("Heading")
        expect(blank_runs(output)).to all(be <= 1)
      end

      it "leaves no blank line when the list is not followed by one" do
        output = render_block("- one\nAfter the list.\n")
        expect(output).to contain("After the list.")
        expect(blank_runs(output)).to be_empty
      end

      it "collapses several blank lines after a list into one" do
        output = render_block("- one\n\n\n\nAfter the list.\n")
        expect(output).to contain("After the list.")
        expect(blank_runs(output)).to all(be <= 1)
      end

      it "separates an ordered list from a following paragraph the same way" do
        output = render_block("1. one\n2. two\n\nAfter the list.\n")
        expect(output).to contain("After the list.")
        expect(blank_runs(output)).to all(be <= 1)
      end
    end
  end
end
