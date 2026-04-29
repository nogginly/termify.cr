require "../ansi"

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
        block_styles : Hash(BlockElement, Style) = {} of BlockElement => Style,
        inline_styles : Hash(InlineElement, Style) = {} of InlineElement => Style,
      )
        @block_styles = block_styles
        @inline_styles = inline_styles
      end

      # Symbol constructor -- maps {:h1 => {bold: true}, :bold => {bold: true}}
      # to the correct enum automatically. Raises for unknown symbols.
      def initialize(styles : Hash(Symbol, NamedTuple))
        @block_styles = {} of BlockElement => Style
        @inline_styles = {} of InlineElement => Style
        styles.each do |sym, opts|
          key = sym.to_s
          sty = style_from(opts)
          if elem = BlockElement.parse?(key)
            @block_styles[elem] = sty
          elsif elem = InlineElement.parse?(key)
            @inline_styles[elem] = sty
          else
            raise "Unknown element: #{sym}"
          end
        end
      end

      # Convert NamedTuple style options into a proper Style
      private def style_from(opts : NamedTuple)
        Style.new(
          bold: opts["bold"]? || false,
          italic: opts["italic"]? || false,
          dim: opts["dim"]? || false,
          underline: opts["underline"]? || false,
          strikethrough: opts["strikethrough"]? || false,
          fg: color_from(opts["fg"]?),
          bg: color_from(opts["bg"]?),
          prefix: opts["prefix"]?,
          suffix: opts["suffix"]?,
        )
      end

      # Convert color value from symbol/string
      private def color_from(value : Symbol | String | Colorize::Color | Nil)
        case value
        when Symbol, String then Colorize::ColorANSI.parse(value.to_s)
        else                     value
        end
      end

      # Look up the style for a block element; returns Style::NONE if not mapped.
      def [](element : BlockElement) : Style
        @block_styles.fetch(element, Style::NONE)
      end

      # Look up the style for an inline element; returns Style::NONE if not mapped.
      def [](element : InlineElement) : Style
        @inline_styles.fetch(element, Style::NONE)
      end

      # Override a single block element entry.
      def []=(element : BlockElement, style : Style) : Style
        @block_styles[element] = style
      end

      # Override a single inline element entry.
      def []=(element : InlineElement, style : Style) : Style
        @inline_styles[element] = style
      end

      # Returns a new Stylesheet with the default built-in theme applied.
      def self.default : Stylesheet
        new(
          block_styles: {
            BlockElement::H1             => Style.new(bold: true, underline: true, fg: Colorize::ColorANSI::White, prefix: "# ", suffix: "\n"),
            BlockElement::H2             => Style.new(bold: true, underline: true, fg: Colorize::ColorANSI::White),
            BlockElement::H3             => Style.new(bold: true, underline: true, fg: Colorize::ColorANSI::LightGray),
            BlockElement::H4             => Style.new(bold: true, underline: true, dim: true),
            BlockElement::H5             => Style.new(italic: true, underline: true, dim: true),
            BlockElement::H6             => Style.new(dim: true, underline: true),
            BlockElement::Paragraph      => Style::NONE,
            BlockElement::Blockquote     => Style.new(prefix: "| "),
            BlockElement::CodeBlock      => Style.new(fg: Colorize::ColorANSI::White, bg: Colorize::ColorANSI::DarkGray),
            BlockElement::HorizontalRule => Style.new(dim: true),
            BlockElement::ListItem       => Style.new(prefix: "* "),
            BlockElement::BlockHtml      => Style.new(fg: Colorize::ColorANSI::Red),
            BlockElement::Table          => Style::NONE,
          } of BlockElement => Style,
          inline_styles: {
            InlineElement::Bold          => Style.new(bold: true),
            InlineElement::Italic        => Style.new(italic: true),
            InlineElement::Strikethrough => Style.new(strikethrough: true),
            InlineElement::CodeInline    => Style.new(fg: Colorize::ColorANSI::Cyan),
            InlineElement::Link          => Style.new(underline: true, fg: Colorize::ColorANSI::LightBlue),
            InlineElement::HtmlTag       => Style.new(fg: Colorize::ColorANSI::Red),
          } of InlineElement => Style,
        )
      end
    end
  end
end
