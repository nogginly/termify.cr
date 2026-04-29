require "../../spec_helper"

Spectator.describe Termify::Markdown::Stylesheet do
  # ── Element enums ───────────────────────────────────────────────────────────

  describe Termify::Markdown::BlockElement do
    it "defines all expected block members" do
      expected = %w[h1 h2 h3 h4 h5 h6 paragraph blockquote codeblock
        listitem horizontalrule blockhtml table]
      expect(Termify::Markdown::BlockElement.names.map(&.downcase)).to eq(expected)
    end
  end

  describe Termify::Markdown::InlineElement do
    it "defines all expected inline members" do
      expected = %w[bold italic strikethrough codeinline link htmltag]
      expect(Termify::Markdown::InlineElement.names.map(&.downcase)).to eq(expected)
    end
  end

  # ── blank slate ─────────────────────────────────────────────────────────────

  describe ".new (blank)" do
    it "returns Style::NONE for any unmapped element" do
      sheet = Termify::Markdown::Stylesheet.new
      expect(sheet[Termify::Markdown::BlockElement::H1]).to eq(Termify::Markdown::Style::NONE)
      expect(sheet[Termify::Markdown::InlineElement::Bold]).to eq(Termify::Markdown::Style::NONE)
    end
  end

  # ── #[]= / #[] round-trip ───────────────────────────────────────────────────

  describe "#[]= and #[]" do
    it "stores and retrieves a style" do
      sheet = Termify::Markdown::Stylesheet.new
      custom = Termify::Markdown::Style.new(bold: true, fg: Colorize::ColorANSI::Red)
      sheet[Termify::Markdown::BlockElement::H1] = custom
      expect(sheet[Termify::Markdown::BlockElement::H1].bold?).to be_true
      expect(sheet[Termify::Markdown::BlockElement::H1].fg).to eq(Colorize::ColorANSI::Red)
    end

    it "overwriting an entry replaces the previous style" do
      sheet = Termify::Markdown::Stylesheet.new
      sheet[Termify::Markdown::InlineElement::Bold] = Termify::Markdown::Style.new(bold: true)
      sheet[Termify::Markdown::InlineElement::Bold] = Termify::Markdown::Style.new(italic: true)
      result = sheet[Termify::Markdown::InlineElement::Bold]
      expect(result.bold?).to be_false
      expect(result.italic?).to be_true
    end

    it "does not affect other elements" do
      sheet = Termify::Markdown::Stylesheet.new
      sheet[Termify::Markdown::BlockElement::H1] = Termify::Markdown::Style.new(bold: true)
      expect(sheet[Termify::Markdown::BlockElement::H2]).to eq(Termify::Markdown::Style::NONE)
    end
  end

  # ── .default theme ──────────────────────────────────────────────────────────

  describe ".default" do
    subject(sheet) { Termify::Markdown::Stylesheet.default }

    it "returns a Stylesheet" do
      expect(sheet).to be_a(Termify::Markdown::Stylesheet)
    end

    it "H1 is bold and underlined" do
      s = sheet[Termify::Markdown::BlockElement::H1]
      expect(s.bold?).to be_true
      expect(s.underline?).to be_true
    end

    it "H1 has a foreground colour set" do
      expect(sheet[Termify::Markdown::BlockElement::H1].fg).not_to be_nil
    end

    it "H2 is bold and underlined" do
      s = sheet[Termify::Markdown::BlockElement::H2]
      expect(s.bold?).to be_true
      expect(s.underline?).to be_true
    end

    it "heading boldness decreases — H4 is dim" do
      expect(sheet[Termify::Markdown::BlockElement::H4].dim?).to be_true
    end

    it "H6 is dim and not bold" do
      s = sheet[Termify::Markdown::BlockElement::H6]
      expect(s.dim?).to be_true
      expect(s.bold?).to be_false
    end

    it "Paragraph maps to Style::NONE" do
      expect(sheet[Termify::Markdown::BlockElement::Paragraph])
        .to eq(Termify::Markdown::Style::NONE)
    end

    it "Blockquote has a line_prefix" do
      expect(sheet[Termify::Markdown::BlockElement::Blockquote].line_prefix).not_to be_nil
    end

    it "CodeBlock has fg and bg set" do
      s = sheet[Termify::Markdown::BlockElement::CodeBlock]
      expect(s.fg).not_to be_nil
      expect(s.bg).not_to be_nil
    end

    it "CodeInline has a fg colour" do
      expect(sheet[Termify::Markdown::InlineElement::CodeInline].fg).not_to be_nil
    end

    it "Bold style is bold" do
      expect(sheet[Termify::Markdown::InlineElement::Bold].bold?).to be_true
    end

    it "Italic style is italic" do
      expect(sheet[Termify::Markdown::InlineElement::Italic].italic?).to be_true
    end

    it "Strikethrough style has strikethrough" do
      expect(sheet[Termify::Markdown::InlineElement::Strikethrough].strikethrough?).to be_true
    end

    it "Link is underlined with a fg colour" do
      s = sheet[Termify::Markdown::InlineElement::Link]
      expect(s.underline?).to be_true
      expect(s.fg).not_to be_nil
    end

    it "ListItem has a line_prefix" do
      expect(sheet[Termify::Markdown::BlockElement::ListItem].line_prefix).not_to be_nil
    end

    it "HtmlTag has a fg colour" do
      s = sheet[Termify::Markdown::InlineElement::HtmlTag]
      expect(s.fg).not_to be_nil
    end

    it "BlockHtml has a fg colour" do
      s = sheet[Termify::Markdown::BlockElement::BlockHtml]
      expect(s.fg).not_to be_nil
    end

    it "each call to .default returns an independent instance" do
      s1 = Termify::Markdown::Stylesheet.default
      s2 = Termify::Markdown::Stylesheet.default
      s1[Termify::Markdown::InlineElement::Bold] = Termify::Markdown::Style::NONE
      expect(s2[Termify::Markdown::InlineElement::Bold].bold?).to be_true
    end
  end

  # ── color_from (symbol color mapping) ───────────────────────────────────────

  describe ".new (symbol constructor) color mapping" do
    it "maps a fg color symbol to the correct Colorize::ColorANSI value" do
      sheet = Termify::Markdown::Stylesheet.new({:paragraph => {fg: :cyan}})
      expect(sheet[Termify::Markdown::BlockElement::Paragraph].fg).to eq(Colorize::ColorANSI::Cyan)
    end

    it "maps a fg color string to the correct Colorize::ColorANSI value" do
      sheet = Termify::Markdown::Stylesheet.new({:paragraph => {fg: "red"}})
      expect(sheet[Termify::Markdown::BlockElement::Paragraph].fg).to eq(Colorize::ColorANSI::Red)
    end

    it "maps a bg color symbol to the correct Colorize::ColorANSI value" do
      sheet = Termify::Markdown::Stylesheet.new({:code_block => {bg: :dark_gray}})
      expect(sheet[Termify::Markdown::BlockElement::CodeBlock].bg).to eq(Colorize::ColorANSI::DarkGray)
    end

    it "passes a Colorize::Color value through unchanged" do
      sheet = Termify::Markdown::Stylesheet.new({:paragraph => {fg: Colorize::ColorANSI::Green}})
      expect(sheet[Termify::Markdown::BlockElement::Paragraph].fg).to eq(Colorize::ColorANSI::Green)
    end

    it "passes a Color256 value through unchanged" do
      color = Colorize::Color256.new(202)
      sheet = Termify::Markdown::Stylesheet.new({:paragraph => {fg: color}})
      expect(sheet[Termify::Markdown::BlockElement::Paragraph].fg).to eq(color)
    end

    it "maps nil fg to nil" do
      sheet = Termify::Markdown::Stylesheet.new({:paragraph => {bold: true}})
      expect(sheet[Termify::Markdown::BlockElement::Paragraph].fg).to be_nil
    end

    it "raises for an unknown color symbol" do
      expect_raises(Exception) do
        Termify::Markdown::Stylesheet.new({:paragraph => {fg: :not_a_color}})
      end
    end
  end
end
