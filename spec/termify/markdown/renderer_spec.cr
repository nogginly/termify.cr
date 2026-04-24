require "../../spec_helper"

Spectator.describe Termify::Markdown::Renderer do
  # Convenience aliases so specs stay readable without full-qualified names.
  include Termify
  include Termify::Markdown

  # Helper: create a fresh renderer, feed one line (appending \n), close it,
  # and return the full output string.
  def render_line(text : String) : String
    io = IO::Memory.new
    r = Renderer.new(io)
    r.feed(text + "\n")
    r.close
    io.to_s
  end

  # Helper: feed a multi-line block without appending an extra newline.
  def render_block(text : String) : String
    io = IO::Memory.new
    r = Renderer.new(io)
    r.feed(text)
    r.close
    io.to_s
  end

  # -------------------------------------------------------------------------
  # Lifecycle
  # -------------------------------------------------------------------------
  describe "lifecycle" do
    let(io) { IO::Memory.new }
    let(renderer) { Renderer.new(io) }

    it "starts open" do
      expect(renderer.closed?).to be_false
    end

    it "is closed after #close" do
      renderer.close
      expect(renderer.closed?).to be_true
    end

    it "#close is idempotent" do
      renderer.close
      renderer.close # must not raise
      expect(renderer.closed?).to be_true
    end

    it "raises when feed is called after close" do
      renderer.close
      expect_raises(Exception, /closed/i) { renderer.feed("x") }
    end
  end

  # -------------------------------------------------------------------------
  # IO interface (Step 8 addition: < IO, write, read)
  # -------------------------------------------------------------------------
  describe "IO interface" do
    let(io) { IO::Memory.new }
    let(renderer) { Renderer.new(io) }

    it "write(Bytes) feeds markdown the same as feed" do
      renderer.write("hello\n".to_slice)
      renderer.close
      expect(io.to_s).to contain("hello")
    end

    it "accepts input via the << operator inherited from IO" do
      renderer << "world\n"
      renderer.close
      expect(io.to_s).to contain("world")
    end

    it "read raises IO::Error" do
      expect_raises(IO::Error) { renderer.read(Bytes.new(4)) }
    end

    it "does not close the output IO when the renderer is closed" do
      renderer.close
      expect(io.closed?).to be_false
    end
  end

  # -------------------------------------------------------------------------
  # Line buffer (Steps 5-6)
  # -------------------------------------------------------------------------
  describe "line buffering" do
    let(io) { IO::Memory.new }
    let(renderer) { Renderer.new(io) }

    it "buffers a partial line until a newline arrives" do
      renderer.feed("par")
      expect(io.to_s).to be_empty
      renderer.feed("tial\n")
      expect(io.to_s).to contain("partial")
    end

    it "flushes the remainder on close even without a trailing newline" do
      renderer.feed("no newline at eof")
      renderer.close
      expect(io.to_s).to contain("no newline at eof")
    end

    it "handles chunks that span multiple lines" do
      renderer.feed("line one\nline two\nline three\n")
      output = io.to_s
      expect(output).to contain("line one")
      expect(output).to contain("line two")
      expect(output).to contain("line three")
    end

    it "handles single-byte chunks correctly" do
      "abc\n".each_char { |c| renderer.feed(c.to_s) }
      expect(io.to_s).to contain("abc")
    end
  end

  # -------------------------------------------------------------------------
  # Block processing (Step 7)
  # -------------------------------------------------------------------------
  describe "block processing" do
    describe "blank lines" do
      it "emits a bare newline for an empty line" do
        output = render_block("\n")
        expect(output).to eq("\n")
      end
    end

    describe "headings" do
      it "applies bold + underline + bright-white fg for H1" do
        output = render_line("# Heading")
        expect(output).to contain(ANSI::BOLD)
        expect(output).to contain(ANSI::UNDERLINE)
        expect(output).to contain(ANSI::FG_BRIGHT_WHITE)
        expect(output).to contain("Heading")
      end

      it "applies bold + bright-white fg for H2" do
        output = render_line("## Heading")
        expect(output).to contain(ANSI::BOLD)
        expect(output).to contain(ANSI::FG_BRIGHT_WHITE)
        expect(output).to contain("Heading")
      end

      it "applies bold + white fg for H3" do
        output = render_line("### Heading")
        expect(output).to contain(ANSI::BOLD)
        expect(output).to contain(ANSI::FG_WHITE)
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

    describe "blockquote" do
      it "emits the '| ' prefix" do
        output = render_line("> quote text")
        expect(output).to contain("| ")
        expect(output).to contain("quote text")
      end

      it "applies italic + dim styling" do
        output = render_line("> quote text")
        expect(output).to contain(ANSI::ITALIC)
        expect(output).to contain(ANSI::DIM)
      end

      it "handles '>' without a trailing space" do
        output = render_line(">no space")
        expect(output).to contain("| ")
        expect(output).to contain("no space")
      end
    end

    describe "code fence" do
      it "emits code-block styling for lines inside a triple-backtick fence" do
        output = render_block("```\nsome code\n```\n")
        expect(output).to contain("some code")
        expect(output).to contain(ANSI::FG_BRIGHT_WHITE)
      end

      it "does not apply inline parsing inside a code fence" do
        output = render_block("```\n**not bold**\n```\n")
        expect(output).to contain("**not bold**")
      end

      it "supports tilde fences" do
        output = render_block("~~~\nsome code\n~~~\n")
        expect(output).to contain("some code")
        expect(output).to contain(ANSI::FG_BRIGHT_WHITE)
      end

      it "returns to normal mode after the closing fence marker" do
        output = render_block("```\ncode\n```\nnormal\n")
        # "normal" should be a paragraph, not code-styled
        # Split at "normal" and check that the code bg is not present after it
        expect(output).to contain("normal")
      end
    end

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

      it "emits '* ' prefix for ordered items" do
        output = render_line("1. item")
        expect(output).to contain("* ")
        expect(output).to contain("item")
      end
    end

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

    describe "block HTML" do
      it "recognises a standalone opening tag" do
        output = render_line("<div>")
        expect(output).to contain("<div>")
        expect(output).to contain(ANSI::FG_RED)
      end

      it "recognises a standalone closing tag" do
        output = render_line("</div>")
        expect(output).to contain("</div>")
        expect(output).to contain(ANSI::FG_RED)
      end

      it "recognises a self-closing tag" do
        output = render_line("<hr/>")
        expect(output).to contain("<hr/>")
        expect(output).to contain(ANSI::FG_RED)
      end

      it "recognises a tag with attributes" do
        output = render_line("<script src=\"app.js\">")
        expect(output).to contain("<script src=\"app.js\">")
        expect(output).to contain(ANSI::FG_RED)
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
        expect(output).to contain(ANSI::FG_RED) # inline tags still styled
        expect(output).to contain("<div>")
        expect(output).to contain("<span>")
      end

      it "does not treat a line with text after the tag as block HTML" do
        output = render_line("<div> some text")
        expect(output).to contain("<div>")
        expect(output).to contain("some text")
        # styled as inline HTML within a paragraph, not as a block HTML line
      end

      it "emits RESET after the tag" do
        output = render_line("<div>")
        red_pos = output.index(ANSI::FG_RED).not_nil!
        reset_pos = output.rindex(ANSI::RESET).not_nil!
        expect(red_pos).to be < reset_pos
      end
    end

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
  end

  # -------------------------------------------------------------------------
  # Inline rendering (Step 8)
  # -------------------------------------------------------------------------
  describe "render_inline" do
    describe "plain text" do
      it "passes text with no markup through unchanged" do
        expect(render_line("hello world")).to contain("hello world")
      end
    end

    describe "bold (**text**)" do
      it "wraps text in BOLD ansi" do
        output = render_line("**bold**")
        expect(output).to contain(ANSI::BOLD)
        expect(output).to contain("bold")
      end

      it "emits RESET after the closing **" do
        output = render_line("**bold**")
        bold_pos = output.index(ANSI::BOLD).not_nil!
        reset_pos = output.rindex(ANSI::RESET).not_nil!
        expect(bold_pos).to be < reset_pos
      end

      it "treats unmatched ** as literal text" do
        output = render_line("no **close here")
        expect(output).to contain("**")
        expect(output).to contain("close here")
        # no bold ANSI emitted
        expect(output).to_not contain(ANSI::BOLD)
      end
    end

    describe "italic (*text*)" do
      it "wraps text in ITALIC ansi" do
        output = render_line("*italic*")
        expect(output).to contain(ANSI::ITALIC)
        expect(output).to contain("italic")
      end

      it "emits RESET after the closing *" do
        output = render_line("*italic*")
        italic_pos = output.index(ANSI::ITALIC).not_nil!
        reset_pos = output.rindex(ANSI::RESET).not_nil!
        expect(italic_pos).to be < reset_pos
      end

      it "treats unmatched * as literal text" do
        output = render_line("no *close here")
        expect(output).to contain("*close")
        expect(output).to_not contain(ANSI::ITALIC)
      end
    end

    describe "italic (_text_)" do
      it "wraps text in ITALIC ansi" do
        output = render_line("_italic_")
        expect(output).to contain(ANSI::ITALIC)
        expect(output).to contain("italic")
      end

      it "treats a mid-word underscore as literal (no italic)" do
        output = render_line("foo_bar_baz")
        expect(output).to contain("foo_bar_baz")
        expect(output).to_not contain(ANSI::ITALIC)
      end

      it "treats unmatched _ as literal text" do
        output = render_line("_no close")
        expect(output).to_not contain(ANSI::ITALIC)
      end
    end

    describe "code span (`text`)" do
      it "applies CodeInline fg (cyan) around the code text" do
        output = render_line("`code`")
        expect(output).to contain(ANSI::FG_CYAN)
        expect(output).to contain("code")
      end

      it "emits RESET after the closing backtick" do
        output = render_line("`code`")
        cyan_pos = output.index(ANSI::FG_CYAN).not_nil!
        reset_pos = output.rindex(ANSI::RESET).not_nil!
        expect(cyan_pos).to be < reset_pos
      end

      it "treats an unmatched backtick as literal" do
        output = render_line("`no close")
        expect(output).to contain("`no close")
        expect(output).to_not contain(ANSI::FG_CYAN)
      end

      it "does not process inline markup inside a code span" do
        output = render_line("`**not bold**`")
        expect(output).to contain("**not bold**")
        expect(output).to_not contain(ANSI::BOLD)
      end
    end

    describe "strikethrough (~~text~~)" do
      it "wraps text in STRIKETHROUGH ansi" do
        output = render_line("~~strike~~")
        expect(output).to contain(ANSI::STRIKETHROUGH)
        expect(output).to contain("strike")
      end

      it "emits RESET after the closing ~~" do
        output = render_line("~~strike~~")
        st_pos = output.index(ANSI::STRIKETHROUGH).not_nil!
        reset_pos = output.rindex(ANSI::RESET).not_nil!
        expect(st_pos).to be < reset_pos
      end

      it "treats unmatched ~~ as literal text" do
        output = render_line("~~no close")
        expect(output).to contain("~~no close")
        expect(output).to_not contain(ANSI::STRIKETHROUGH)
      end
    end

    describe "inline HTML tags" do
      it "preserves the tag text verbatim" do
        output = render_line("text <em>here</em> end")
        expect(output).to contain("<em>")
        expect(output).to contain("</em>")
      end

      it "applies FG_RED to the tag" do
        output = render_line("text <em>here</em> end")
        expect(output).to contain(ANSI::FG_RED)
      end

      it "emits RESET after the tag" do
        output = render_line("text <em>here</em> end")
        red_pos = output.index(ANSI::FG_RED).not_nil!
        reset_pos = output.rindex(ANSI::RESET).not_nil!
        expect(red_pos).to be < reset_pos
      end

      it "handles self-closing tags" do
        output = render_line("line break<br/> here")
        expect(output).to contain("<br/>")
        expect(output).to contain(ANSI::FG_RED)
      end

      it "handles closing tags" do
        output = render_line("</div>")
        expect(output).to contain("</div>")
        expect(output).to contain(ANSI::FG_RED)
      end

      it "treats a bare '<' with no valid tag as a literal" do
        output = render_line("a < b")
        expect(output).to contain("< b")
        expect(output).to_not contain(ANSI::FG_RED)
      end

      it "handles multiple tags on one line" do
        output = render_line("<strong>bold</strong> and <em>italic</em>")
        expect(output).to contain("<strong>")
        expect(output).to contain("</strong>")
        expect(output).to contain("<em>")
        expect(output).to contain("</em>")
      end

      it "preserves surrounding text unchanged" do
        output = render_line("before <b>tag</b> after")
        expect(output).to contain("before")
        expect(output).to contain("tag")
        expect(output).to contain("after")
      end

      it "does not apply HTML tag styling inside a code fence" do
        output = render_block("```\n<em>not styled</em>\n```\n")
        expect(output).to contain("<em>not styled</em>")
        expect(output).to_not contain(ANSI::FG_RED)
      end
    end

    describe "link spans ([text](url))" do
      it "renders the link text" do
        output = render_line("[click here](https://example.com)")
        expect(output).to contain("click here")
      end

      it "suppresses the URL" do
        output = render_line("[click here](https://example.com)")
        expect(output).to_not contain("https://example.com")
      end

      it "applies underline to link text" do
        output = render_line("[click here](https://example.com)")
        expect(output).to contain(ANSI::UNDERLINE)
      end

      it "applies FG_BRIGHT_BLUE to link text" do
        output = render_line("[click here](https://example.com)")
        expect(output).to contain(ANSI::FG_BRIGHT_BLUE)
      end

      it "emits RESET after the link" do
        output = render_line("[click here](https://example.com)")
        blue_pos = output.index(ANSI::FG_BRIGHT_BLUE).not_nil!
        reset_pos = output.rindex(ANSI::RESET).not_nil!
        expect(blue_pos).to be < reset_pos
      end

      it "treats unmatched '[' as literal" do
        output = render_line("no [close here")
        expect(output).to contain("[close here")
        expect(output).to_not contain(ANSI::UNDERLINE)
      end

      it "treats '[text]' without '(url)' as literal" do
        output = render_line("[text] no parens")
        expect(output).to contain("[text]")
        expect(output).to_not contain(ANSI::FG_BRIGHT_BLUE)
      end

      it "renders bold inside link text" do
        output = render_line("[**bold** link](https://example.com)")
        expect(output).to contain("bold")
        expect(output).to contain(ANSI::BOLD)
        expect(output).to_not contain("https://example.com")
      end

      it "renders multiple links on one line" do
        output = render_line("[one](https://a.com) and [two](https://b.com)")
        expect(output).to contain("one")
        expect(output).to contain("two")
        expect(output).to_not contain("https://a.com")
        expect(output).to_not contain("https://b.com")
      end
    end

    describe "nesting" do
      it "renders bold containing italic with both ANSI codes present" do
        output = render_line("**bold *italic* bold**")
        expect(output).to contain(ANSI::BOLD)
        expect(output).to contain(ANSI::ITALIC)
        expect(output).to contain("bold")
        expect(output).to contain("italic")
      end

      it "restores bold after closing italic inside bold" do
        # After *italic* closes, BOLD must reappear before the trailing 'bold'.
        output = render_line("**outer *inner* outer**")
        # BOLD appears at least twice: once on open, once on replay after italic close
        expect(output.scan(ANSI::BOLD).size).to be >= 2
      end

      it "renders italic containing a code span" do
        output = render_line("*italic `code` italic*")
        expect(output).to contain(ANSI::ITALIC)
        expect(output).to contain(ANSI::FG_CYAN)
        expect(output).to contain("code")
      end
    end

    describe "inline inside block" do
      it "renders bold inside a heading" do
        output = render_line("# Title with **bold**")
        expect(output).to contain(ANSI::FG_BRIGHT_WHITE) # heading style
        expect(output).to contain(ANSI::BOLD)            # both heading and inline bold
        expect(output).to contain("Title with")
        expect(output).to contain("bold")
      end

      it "renders code span inside a blockquote" do
        output = render_line("> quote with `code` inside")
        expect(output).to contain("| ")          # blockquote prefix
        expect(output).to contain(ANSI::FG_CYAN) # code inline
        expect(output).to contain("code")
      end
    end

    describe "mixed inline markup on one line" do
      it "handles bold, italic, and code on the same line" do
        output = render_line("**a** *b* `c`")
        expect(output).to contain(ANSI::BOLD)
        expect(output).to contain(ANSI::ITALIC)
        expect(output).to contain(ANSI::FG_CYAN)
        expect(output).to contain("a")
        expect(output).to contain("b")
        expect(output).to contain("c")
      end
    end
  end
end
