require "../../spec_helper"

Spectator.describe Termify::Markdown::Stylesheet do
  # ── Element enum ────────────────────────────────────────────────────────────

  describe Termify::Markdown::Element do
    it "defines all expected members" do
      expected = %w[h1 h2 h3 h4 h5 h6 paragraph blockquote codeblock
        codeinline bold italic strikethrough link listitem
        horizontalrule htmltag blockhtml]
      expect(Termify::Markdown::Element.names.map(&.downcase)).to eq(expected)
    end
  end

  # ── blank slate ─────────────────────────────────────────────────────────────

  describe ".new (blank)" do
    it "returns Style::NONE for any unmapped element" do
      sheet = Termify::Markdown::Stylesheet.new
      expect(sheet[Termify::Markdown::Element::H1]).to eq(Termify::Markdown::Style::NONE)
      expect(sheet[Termify::Markdown::Element::Bold]).to eq(Termify::Markdown::Style::NONE)
    end
  end

  # ── #[]= / #[] round-trip ───────────────────────────────────────────────────

  describe "#[]= and #[]" do
    it "stores and retrieves a style" do
      sheet = Termify::Markdown::Stylesheet.new
      custom = Termify::Markdown::Style.new(bold: true, fg: Termify::ANSI::FG_RED)
      sheet[Termify::Markdown::Element::H1] = custom
      expect(sheet[Termify::Markdown::Element::H1].bold).to be_true
      expect(sheet[Termify::Markdown::Element::H1].fg).to eq(Termify::ANSI::FG_RED)
    end

    it "overwriting an entry replaces the previous style" do
      sheet = Termify::Markdown::Stylesheet.new
      sheet[Termify::Markdown::Element::Bold] = Termify::Markdown::Style.new(bold: true)
      sheet[Termify::Markdown::Element::Bold] = Termify::Markdown::Style.new(italic: true)
      result = sheet[Termify::Markdown::Element::Bold]
      expect(result.bold).to be_false
      expect(result.italic).to be_true
    end

    it "does not affect other elements" do
      sheet = Termify::Markdown::Stylesheet.new
      sheet[Termify::Markdown::Element::H1] = Termify::Markdown::Style.new(bold: true)
      expect(sheet[Termify::Markdown::Element::H2]).to eq(Termify::Markdown::Style::NONE)
    end
  end

  # ── .default theme ──────────────────────────────────────────────────────────

  describe ".default" do
    subject(sheet) { Termify::Markdown::Stylesheet.default }

    it "returns a Stylesheet" do
      expect(sheet).to be_a(Termify::Markdown::Stylesheet)
    end

    it "H1 is bold and underlined" do
      s = sheet[Termify::Markdown::Element::H1]
      expect(s.bold).to be_true
      expect(s.underline).to be_true
    end

    it "H1 has a foreground colour set" do
      expect(sheet[Termify::Markdown::Element::H1].fg).not_to be_nil
    end

    it "H2 is bold but not underlined" do
      s = sheet[Termify::Markdown::Element::H2]
      expect(s.bold).to be_true
      expect(s.underline).to be_false
    end

    it "heading boldness decreases — H4 is dim" do
      expect(sheet[Termify::Markdown::Element::H4].dim).to be_true
    end

    it "H6 is dim and not bold" do
      s = sheet[Termify::Markdown::Element::H6]
      expect(s.dim).to be_true
      expect(s.bold).to be_false
    end

    it "Paragraph maps to Style::NONE" do
      expect(sheet[Termify::Markdown::Element::Paragraph])
        .to eq(Termify::Markdown::Style::NONE)
    end

    it "Blockquote has a prefix" do
      expect(sheet[Termify::Markdown::Element::Blockquote].prefix).not_to be_nil
    end

    it "Blockquote is italic and dim" do
      s = sheet[Termify::Markdown::Element::Blockquote]
      expect(s.italic).to be_true
      expect(s.dim).to be_true
    end

    it "CodeBlock has fg and bg set" do
      s = sheet[Termify::Markdown::Element::CodeBlock]
      expect(s.fg).not_to be_nil
      expect(s.bg).not_to be_nil
    end

    it "CodeInline has a fg colour" do
      expect(sheet[Termify::Markdown::Element::CodeInline].fg).not_to be_nil
    end

    it "Bold style is bold" do
      expect(sheet[Termify::Markdown::Element::Bold].bold).to be_true
    end

    it "Italic style is italic" do
      expect(sheet[Termify::Markdown::Element::Italic].italic).to be_true
    end

    it "Strikethrough style has strikethrough" do
      expect(sheet[Termify::Markdown::Element::Strikethrough].strikethrough).to be_true
    end

    it "Link is underlined with a fg colour" do
      s = sheet[Termify::Markdown::Element::Link]
      expect(s.underline).to be_true
      expect(s.fg).not_to be_nil
    end

    it "ListItem has a prefix" do
      expect(sheet[Termify::Markdown::Element::ListItem].prefix).not_to be_nil
    end

    it "HtmlTag has a fg colour" do
      s = sheet[Termify::Markdown::Element::HtmlTag]
      expect(s.fg).not_to be_nil
    end

    it "BlockHtml has a fg colour" do
      s = sheet[Termify::Markdown::Element::BlockHtml]
      expect(s.fg).not_to be_nil
    end

    it "each call to .default returns an independent instance" do
      s1 = Termify::Markdown::Stylesheet.default
      s2 = Termify::Markdown::Stylesheet.default
      s1[Termify::Markdown::Element::Bold] = Termify::Markdown::Style::NONE
      expect(s2[Termify::Markdown::Element::Bold].bold).to be_true
    end
  end
end
