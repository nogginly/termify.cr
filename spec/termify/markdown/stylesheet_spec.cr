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
    it "returns the appropriate NONE for any unmapped element" do
      sheet = Termify::Markdown::Stylesheet.new
      expect(sheet[Termify::Markdown::BlockElement::H1]).to eq(Termify::Markdown::BlockStyle::NONE)
      expect(sheet[Termify::Markdown::InlineElement::Bold]).to eq(Termify::Markdown::InlineStyle::NONE)
    end
  end

  # ── #[]= / #[] round-trip ───────────────────────────────────────────────────

  describe "#[]= and #[]" do
    it "stores and retrieves a style" do
      sheet = Termify::Markdown::Stylesheet.new
      custom = Termify::Markdown::BlockStyle.new(bold: true, fg: Colorize::ColorANSI::Red)
      sheet[Termify::Markdown::BlockElement::H1] = custom
      expect(sheet[Termify::Markdown::BlockElement::H1].bold?).to be_true
      expect(sheet[Termify::Markdown::BlockElement::H1].fg).to eq(Colorize::ColorANSI::Red)
    end

    it "overwriting an entry replaces the previous style" do
      sheet = Termify::Markdown::Stylesheet.new
      sheet[Termify::Markdown::InlineElement::Bold] = Termify::Markdown::InlineStyle.new(bold: true)
      sheet[Termify::Markdown::InlineElement::Bold] = Termify::Markdown::InlineStyle.new(italic: true)
      result = sheet[Termify::Markdown::InlineElement::Bold]
      expect(result.bold?).to be_false
      expect(result.italic?).to be_true
    end

    it "does not affect other elements" do
      sheet = Termify::Markdown::Stylesheet.new
      sheet[Termify::Markdown::BlockElement::H1] = Termify::Markdown::BlockStyle.new(bold: true)
      expect(sheet[Termify::Markdown::BlockElement::H2]).to eq(Termify::Markdown::BlockStyle::NONE)
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
        .to eq(Termify::Markdown::BlockStyle::NONE)
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

    it "newline_before and newline_after are false for all entries in the default theme" do
      Termify::Markdown::BlockElement.each do |elem|
        s = sheet[elem]
        expect(s.newline_before?).to be_false
        expect(s.newline_after?).to be_false
      end
    end

    it "each call to .default returns an independent instance" do
      s1 = Termify::Markdown::Stylesheet.default
      s2 = Termify::Markdown::Stylesheet.default
      s1[Termify::Markdown::InlineElement::Bold] = Termify::Markdown::InlineStyle::NONE
      expect(s2[Termify::Markdown::InlineElement::Bold].bold?).to be_true
    end
  end

  # ── newline_before / newline_after rendering ─────────────────────────────────

  describe "newline_before and newline_after collapse at block boundaries" do
    it "emits one blank line between two blocks when outgoing has newline_after" do
      sheet = Termify::Markdown::Stylesheet.new
      sheet[Termify::Markdown::BlockElement::H1] =
        Termify::Markdown::BlockStyle.new(bold: true, newline_after: true)
      sheet[Termify::Markdown::BlockElement::Paragraph] =
        Termify::Markdown::BlockStyle.new
      output = String.build do |io|
        r = Termify::Markdown::Renderer.new(io, sheet)
        r << "# Heading\nParagraph text\n"
        r.close
      end
      # One blank line between heading and paragraph, not two
      expect(output).to contain("\n\nParagraph")
      expect(output).not_to contain("\n\n\nParagraph")
    end

    it "emits one blank line between two blocks when incoming has newline_before" do
      sheet = Termify::Markdown::Stylesheet.new
      sheet[Termify::Markdown::BlockElement::H1] =
        Termify::Markdown::BlockStyle.new(bold: true)
      sheet[Termify::Markdown::BlockElement::Paragraph] =
        Termify::Markdown::BlockStyle.new(newline_before: true)
      output = String.build do |io|
        r = Termify::Markdown::Renderer.new(io, sheet)
        r << "# Heading\nParagraph text\n"
        r.close
      end
      expect(output).to contain("\n\nParagraph")
      expect(output).not_to contain("\n\n\nParagraph")
    end

    it "emits only one blank line when both outgoing newline_after and incoming newline_before are set" do
      sheet = Termify::Markdown::Stylesheet.new
      sheet[Termify::Markdown::BlockElement::H1] =
        Termify::Markdown::BlockStyle.new(bold: true, newline_after: true)
      sheet[Termify::Markdown::BlockElement::Paragraph] =
        Termify::Markdown::BlockStyle.new(newline_before: true)
      output = String.build do |io|
        r = Termify::Markdown::Renderer.new(io, sheet)
        r << "# Heading\nParagraph text\n"
        r.close
      end
      expect(output).to contain("\n\nParagraph")
      expect(output).not_to contain("\n\n\nParagraph")
    end

    it "does not accumulate blank lines between same-type blocks separated by a blank line" do
      sheet = Termify::Markdown::Stylesheet.new
      sheet[Termify::Markdown::BlockElement::Blockquote] =
        Termify::Markdown::BlockStyle.new(newline_before: true, newline_after: true)
      output = String.build do |io|
        r = Termify::Markdown::Renderer.new(io, sheet)
        r << "> Note\n\n> Warning\n"
        r.close
      end
      expect(output).not_to contain("\n\n\n")
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

    it "maps a lowercase hex string to a ColorRGB value" do
      sheet = Termify::Markdown::Stylesheet.new({:paragraph => {fg: "#ff8000"}})
      result = sheet[Termify::Markdown::BlockElement::Paragraph].fg
      expect(result).to be_a(Colorize::ColorRGB)
      rgb = result.as(Colorize::ColorRGB)
      expect(rgb.red).to eq(0xff_u8)
      expect(rgb.green).to eq(0x80_u8)
      expect(rgb.blue).to eq(0x00_u8)
    end

    it "maps an uppercase hex string to a ColorRGB value" do
      sheet = Termify::Markdown::Stylesheet.new({:paragraph => {fg: "#FF8000"}})
      expect(sheet[Termify::Markdown::BlockElement::Paragraph].fg).to be_a(Colorize::ColorRGB)
    end

    it "raises for a hex string with extra trailing characters" do
      expect_raises(Exception) do
        Termify::Markdown::Stylesheet.new({:paragraph => {fg: "#ff80001"}})
      end
    end

    it "raises for a hex string embedded in other text" do
      expect_raises(Exception) do
        Termify::Markdown::Stylesheet.new({:paragraph => {fg: "color#ff8000"}})
      end
    end

    it "raises for a hex string with too few digits" do
      expect_raises(Exception) do
        Termify::Markdown::Stylesheet.new({:paragraph => {fg: "#ff80"}})
      end
    end

    it "maps a Color256 name string to an ANSI::Color256 value" do
      sheet = Termify::Markdown::Stylesheet.new({:paragraph => {fg: "DeepSkyBlue1"}})
      expect(sheet[Termify::Markdown::BlockElement::Paragraph].fg).to be_a(Termify::ANSI::Color256)
    end

    it "maps a named ANSI::Color256 enum value through unchanged" do
      color = Termify::ANSI::Color256::Red
      sheet = Termify::Markdown::Stylesheet.new({:paragraph => {fg: color}})
      expect(sheet[Termify::Markdown::BlockElement::Paragraph].fg).to eq(color)
    end

    it "maps nil fg to nil" do
      sheet = Termify::Markdown::Stylesheet.new({:paragraph => {bold: true}})
      expect(sheet[Termify::Markdown::BlockElement::Paragraph].fg).to be_nil
    end

    it "maps newline_before: true correctly" do
      sheet = Termify::Markdown::Stylesheet.new({:paragraph => {newline_before: true}})
      expect(sheet[Termify::Markdown::BlockElement::Paragraph].newline_before?).to be_true
    end

    it "maps newline_after: true correctly" do
      sheet = Termify::Markdown::Stylesheet.new({:paragraph => {newline_after: true}})
      expect(sheet[Termify::Markdown::BlockElement::Paragraph].newline_after?).to be_true
    end

    it "defaults newline_before and newline_after to false when absent" do
      sheet = Termify::Markdown::Stylesheet.new({:paragraph => {bold: true}})
      s = sheet[Termify::Markdown::BlockElement::Paragraph]
      expect(s.newline_before?).to be_false
      expect(s.newline_after?).to be_false
    end

    it "raises for an unknown color symbol" do
      expect_raises(Exception) do
        Termify::Markdown::Stylesheet.new({:paragraph => {fg: :not_a_color}})
      end
    end
  end

  # -- .new(styles, merge:) -------------------------------------------------------

  describe ".new with merge:" do
    it "inherits entries from the base stylesheet" do
      base = Termify::Markdown::Stylesheet.new({:paragraph => {bold: true}})
      derived = Termify::Markdown::Stylesheet.new({} of Symbol => NamedTuple(), merge: base)
      expect(derived[Termify::Markdown::BlockElement::Paragraph].bold?).to be_true
    end

    it "overrides a base entry with the new value" do
      base = Termify::Markdown::Stylesheet.new({:paragraph => {bold: true}})
      derived = Termify::Markdown::Stylesheet.new({:paragraph => {italic: true}}, merge: base)
      result = derived[Termify::Markdown::BlockElement::Paragraph]
      expect(result.bold?).to be_false
      expect(result.italic?).to be_true
    end

    it "does not mutate the base stylesheet when adding a new entry" do
      base = Termify::Markdown::Stylesheet.new({:paragraph => {bold: true}})
      Termify::Markdown::Stylesheet.new({:blockquote => {italic: true}}, merge: base)
      expect(base[Termify::Markdown::BlockElement::Blockquote]).to eq(Termify::Markdown::BlockStyle::NONE)
    end

    it "does not mutate the base stylesheet when overriding an existing entry" do
      base = Termify::Markdown::Stylesheet.new({:paragraph => {bold: true}})
      Termify::Markdown::Stylesheet.new({:paragraph => {italic: true}}, merge: base)
      expect(base[Termify::Markdown::BlockElement::Paragraph].bold?).to be_true
      expect(base[Termify::Markdown::BlockElement::Paragraph].italic?).to be_false
    end

    it "falls back to NONE for elements absent from both base and overrides" do
      base = Termify::Markdown::Stylesheet.new({:paragraph => {bold: true}})
      derived = Termify::Markdown::Stylesheet.new({} of Symbol => NamedTuple(), merge: base)
      expect(derived[Termify::Markdown::BlockElement::H1]).to eq(Termify::Markdown::BlockStyle::NONE)
    end

    it "works correctly with Stylesheet.default as the base" do
      derived = Termify::Markdown::Stylesheet.new({:paragraph => {bold: true}},
        merge: Termify::Markdown::Stylesheet.default)
      expect(derived[Termify::Markdown::BlockElement::Paragraph].bold?).to be_true
      # default H1 entry should still be present
      expect(derived[Termify::Markdown::BlockElement::H1].bold?).to be_true
    end

    it "does not mutate Stylesheet.default when used as base" do
      base = Termify::Markdown::Stylesheet.default
      Termify::Markdown::Stylesheet.new({:paragraph => {bold: true}}, merge: base)
      expect(base[Termify::Markdown::BlockElement::Paragraph]).to eq(Termify::Markdown::BlockStyle::NONE)
    end
  end
end
