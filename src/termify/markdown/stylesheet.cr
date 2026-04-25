require "../ansi"

module Termify
  module Markdown
    # Identifies every markdown element the renderer recognises.
    enum Element
      H1
      H2
      H3
      H4
      H5
      H6
      Paragraph
      Blockquote
      CodeBlock
      CodeInline
      Bold
      Italic
      Strikethrough
      Link
      ListItem
      HorizontalRule
      HtmlTag
      BlockHtml
      Table
    end

    # Maps Element → Style.  Missing entries fall back to Style::NONE.
    # Immutable after construction except via #[]=; use .default for the
    # built-in theme, or start from Stylesheet.new for a blank slate.
    class Stylesheet
      def initialize(@styles : Hash(Element, Style) = {} of Element => Style)
      end

      def initialize(styles : Hash(Symbol, NamedTuple))
        @styles = {} of Element => Style
        styles.each do |sym, opts|
          elem = Element.parse(sym.to_s)
          sty = Style.new(
            bold: opts["bold"]? || false,
            italic: opts["italic"]? || false,
            dim: opts["dim"]? || false,
            underline: opts["underline"]? || false,
            strikethrough: opts["strikethrough"]? || false,
            fg: opts["fg"]? || nil,
            bg: opts["bg"]? || nil,
            prefix: opts["prefix"]? || nil,
            suffix: opts["suffix"]? || nil,
          )
          @styles[elem] = sty
        end
      end

      # Look up the style for *element*; returns Style::NONE if not mapped.
      def [](element : Element) : Style
        @styles.fetch(element, Style::NONE)
      end

      # Override a single entry (for user customisation).
      def []=(element : Element, style : Style) : Style
        @styles[element] = style
      end

      # Returns a new Stylesheet with the default built-in theme applied.
      def self.default : Stylesheet
        new({
          # ── headings — bold + colour hierarchy, no literal prefix ───────
          Element::H1 => Style.new(bold: true, underline: true, fg: ANSI::FG_BRIGHT_WHITE, prefix: "# ", suffix: "\n"),
          Element::H2 => Style.new(bold: true, underline: true, fg: ANSI::FG_BRIGHT_WHITE),
          Element::H3 => Style.new(bold: true, underline: true, fg: ANSI::FG_WHITE),
          Element::H4 => Style.new(bold: true, underline: true, dim: true),
          Element::H5 => Style.new(italic: true, underline: true, dim: true),
          Element::H6 => Style.new(dim: true, underline: true),

          # ── block elements ───────────────────────────────────────────────
          Element::Paragraph      => Style::NONE,
          Element::Blockquote     => Style.new(prefix: "| "),
          Element::CodeBlock      => Style.new(fg: ANSI::FG_BRIGHT_WHITE, bg: ANSI::BG_BRIGHT_BLACK),
          Element::HorizontalRule => Style.new(dim: true),
          Element::ListItem       => Style.new(prefix: "* "),

          # ── inline elements ──────────────────────────────────────────────
          Element::CodeInline    => Style.new(fg: ANSI::FG_CYAN),
          Element::Bold          => Style.new(bold: true),
          Element::Italic        => Style.new(italic: true),
          Element::Strikethrough => Style.new(strikethrough: true),
          Element::Link          => Style.new(underline: true, fg: ANSI::FG_BRIGHT_BLUE),
          Element::HtmlTag       => Style.new(fg: ANSI::FG_RED),
          Element::BlockHtml     => Style.new(fg: ANSI::FG_RED),
          Element::Table         => Style::NONE,
        } of Element => Style)
      end
    end
  end
end
