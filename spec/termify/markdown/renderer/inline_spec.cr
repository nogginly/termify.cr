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
        expect(output).to contain("\e[36m")
        expect(output).to contain("code")
      end

      it "emits RESET after the closing backtick" do
        output = render_line("`code`")
        cyan_pos = output.index("\e[36m").not_nil!
        reset_pos = output.rindex(ANSI::RESET).not_nil!
        expect(cyan_pos).to be < reset_pos
      end

      it "treats an unmatched backtick as literal" do
        output = render_line("`no close")
        expect(output).to contain("`no close")
        expect(output).to_not contain("\e[36m")
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
        expect(output).to contain("\e[31m")
      end

      it "emits RESET after the tag" do
        output = render_line("text <em>here</em> end")
        red_pos = output.index("\e[31m").not_nil!
        reset_pos = output.rindex(ANSI::RESET).not_nil!
        expect(red_pos).to be < reset_pos
      end

      it "handles self-closing tags" do
        output = render_line("line break<br/> here")
        expect(output).to contain("<br/>")
        expect(output).to contain("\e[31m")
      end

      it "handles closing tags" do
        output = render_line("</div>")
        expect(output).to contain("</div>")
        expect(output).to contain("\e[31m")
      end

      it "treats a bare '<' with no valid tag as a literal" do
        output = render_line("a < b")
        expect(output).to contain("< b")
        expect(output).to_not contain("\e[31m")
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
        expect(output).to_not contain("\e[31m")
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
        expect(output).to contain("\e[94m")
      end

      it "emits RESET after the link" do
        output = render_line("[click here](https://example.com)")
        blue_pos = output.index("\e[94m").not_nil!
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
        expect(output).to_not contain("\e[94m")
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
        output = render_line("**outer *inner* outer**")
        # BOLD appears at least twice: once on open, once on replay after italic close
        expect(output.scan(ANSI::BOLD).size).to be >= 2
      end

      it "renders italic containing a code span" do
        output = render_line("*italic `code` italic*")
        expect(output).to contain(ANSI::ITALIC)
        expect(output).to contain("\e[36m")
        expect(output).to contain("code")
      end
    end

    describe "inline inside block" do
      it "renders bold inside a heading" do
        output = render_line("# Title with **bold**")
        expect(output).to contain("\e[97m")   # heading style
        expect(output).to contain(ANSI::BOLD) # both heading and inline bold
        expect(output).to contain("Title with")
        expect(output).to contain("bold")
      end

      it "renders code span inside a blockquote" do
        output = render_line("> quote with `code` inside")
        expect(output).to contain("| ")     # blockquote prefix
        expect(output).to contain("\e[36m") # code inline
        expect(output).to contain("code")
      end
    end

    describe "mixed inline markup on one line" do
      it "handles bold, italic, and code on the same line" do
        output = render_line("**a** *b* `c`")
        expect(output).to contain(ANSI::BOLD)
        expect(output).to contain(ANSI::ITALIC)
        expect(output).to contain("\e[36m")
        expect(output).to contain("a")
        expect(output).to contain("b")
        expect(output).to contain("c")
      end
    end
  end
end
