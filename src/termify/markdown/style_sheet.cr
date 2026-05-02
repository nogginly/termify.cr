require "./style"

module Termify
  module Markdown
    # Block-level markdown elements. Styled via BlockStyle entries in Stylesheet.
    enum BlockElement
      H1
      H2
      H3
      H4
      H5
      H6
      Paragraph
      Blockquote
      CodeBlock
      ListItem
      HorizontalRule
      BlockHtml
      Table
    end

    # Inline markdown elements. Styled via Style entries in Stylesheet.
    enum InlineElement
      Bold
      Italic
      Strikethrough
      CodeInline
      Link
      HtmlTag
    end

    # Maps block and inline elements to their styles independently.
    # Missing entries fall back to Style::NONE.
    # Use .default for the built-in theme, or .new for a blank slate.
    class Stylesheet
      def initialize(
        block_styles : Hash(BlockElement, BlockStyle) = {} of BlockElement => BlockStyle,
        inline_styles : Hash(InlineElement, InlineStyle) = {} of InlineElement => InlineStyle,
      )
        @block_styles = block_styles
        @inline_styles = inline_styles
      end

      # Symbol/String constructor -- maps {:h1 => {bold: true}, "bold" => {bold: true}}
      # to the correct enum automatically. Raises for unknown symbols.
      def initialize(styles : Hash(Symbol | String, NamedTuple), merge : Stylesheet? = nil)
        if merge.nil?
          @block_styles = {} of BlockElement => BlockStyle
          @inline_styles = {} of InlineElement => InlineStyle
        else
          @block_styles = merge.@block_styles.dup
          @inline_styles = merge.@inline_styles.dup
        end

        styles.each do |sym, opts|
          key = sym.to_s
          if elem = BlockElement.parse?(key)
            @block_styles[elem] = block_style_from(opts)
          elsif elem = InlineElement.parse?(key)
            @inline_styles[elem] = inline_style_from(opts)
          else
            raise "Unknown element: #{sym}"
          end
        end
      end

      # Convert NamedTuple options into a BlockStyle.
      private def block_style_from(opts : NamedTuple) : BlockStyle
        BlockStyle.new(
          bold: opts["bold"]? || false,
          italic: opts["italic"]? || false,
          dim: opts["dim"]? || false,
          underline: opts["underline"]? || false,
          strikethrough: opts["strikethrough"]? || false,
          fg: color_from(opts["fg"]?),
          bg: color_from(opts["bg"]?),
          line_prefix: opts["line_prefix"]?,
          line_suffix: opts["line_suffix"]?,
          newline_before: opts["newline_before"]? || false,
          newline_after: opts["newline_after"]? || false,
        )
      end

      # Convert NamedTuple options into an InlineStyle.
      private def inline_style_from(opts : NamedTuple) : InlineStyle
        InlineStyle.new(
          bold: opts["bold"]? || false,
          italic: opts["italic"]? || false,
          dim: opts["dim"]? || false,
          underline: opts["underline"]? || false,
          strikethrough: opts["strikethrough"]? || false,
          fg: color_from(opts["fg"]?),
          bg: color_from(opts["bg"]?),
        )
      end

      # Matches a full hex color string e.g. "#ff8000" or "#FF8000".
      # Anchored so superstrings do not match; case-insensitive for A-F.
      private HEX_COLOR_RE = /\A#([0-9a-fA-F]{6})\z/

      # Convert color value from symbol/string
      private def color_from(value : Symbol | String | ANSI::Color | Nil)
        case value
        when Symbol, String
          case value.to_s
          when HEX_COLOR_RE
            rgb = $~[1]
            Colorize::ColorRGB.new(
              red: rgb[0..1].to_u8(16),
              green: rgb[2..3].to_u8(16),
              blue: rgb[4..5].to_u8(16))
          else
            Colorize::ColorANSI.parse?(value.to_s) ||
              ANSI::Color256.parse(value.to_s)
          end
        else
          value
        end
      end

      # Look up the style for a block element; returns BlockStyle::NONE if not mapped.
      def [](element : BlockElement) : BlockStyle
        @block_styles.fetch(element, BlockStyle::NONE)
      end

      # Look up the style for an inline element; returns InlineStyle::NONE if not mapped.
      def [](element : InlineElement) : InlineStyle
        @inline_styles.fetch(element, InlineStyle::NONE)
      end

      # Override a single block element entry.
      def []=(element : BlockElement, style : BlockStyle) : BlockStyle
        @block_styles[element] = style
      end

      # Override a single inline element entry.
      def []=(element : InlineElement, style : InlineStyle) : InlineStyle
        @inline_styles[element] = style
      end

      # Returns a new Stylesheet with the default built-in theme applied.
      def self.default : Stylesheet
        new(
          block_styles: {
            BlockElement::H1             => BlockStyle.new(bold: true, underline: true, fg: Colorize::ColorANSI::White, line_prefix: "# ", line_suffix: "\n"),
            BlockElement::H2             => BlockStyle.new(bold: true, underline: true, fg: Colorize::ColorANSI::White),
            BlockElement::H3             => BlockStyle.new(bold: true, underline: true, fg: Colorize::ColorANSI::LightGray),
            BlockElement::H4             => BlockStyle.new(bold: true, underline: true, dim: true),
            BlockElement::H5             => BlockStyle.new(italic: true, underline: true, dim: true),
            BlockElement::H6             => BlockStyle.new(dim: true, underline: true),
            BlockElement::Paragraph      => BlockStyle::NONE,
            BlockElement::Blockquote     => BlockStyle.new(line_prefix: "| "),
            BlockElement::CodeBlock      => BlockStyle.new(fg: Colorize::ColorANSI::White, bg: Colorize::ColorANSI::DarkGray),
            BlockElement::HorizontalRule => BlockStyle.new(dim: true),
            BlockElement::ListItem       => BlockStyle.new(line_prefix: "* "),
            BlockElement::BlockHtml      => BlockStyle.new(fg: Colorize::ColorANSI::Red),
            BlockElement::Table          => BlockStyle::NONE,
          } of BlockElement => BlockStyle,
          inline_styles: {
            InlineElement::Bold          => InlineStyle.new(bold: true),
            InlineElement::Italic        => InlineStyle.new(italic: true),
            InlineElement::Strikethrough => InlineStyle.new(strikethrough: true),
            InlineElement::CodeInline    => InlineStyle.new(fg: Colorize::ColorANSI::Cyan),
            InlineElement::Link          => InlineStyle.new(underline: true, fg: Colorize::ColorANSI::LightBlue),
            InlineElement::HtmlTag       => InlineStyle.new(fg: Colorize::ColorANSI::Red),
          } of InlineElement => InlineStyle,
        )
      end
    end
  end
end
