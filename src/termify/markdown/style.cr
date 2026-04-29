require "../ansi"

module Termify
  module Markdown
    # Immutable value object describing the visual style for one markdown element.
    #
    # Attributes map directly to ANSI SGR flags plus optional fg/bg sequences
    # (any string produced by ANSI.*) and optional literal prefix/suffix strings
    # that bracket rendered text at the block level (e.g. "│ " for blockquotes).
    #
    # Composition: `base.merge(override)` returns a new Style where override
    # wins for every attribute it sets, leaving the rest from base.
    #
    # Equality: two Style instances are equal when all fields match (value semantics).
    class Style
      getter? bold : Bool
      getter? italic : Bool
      getter? dim : Bool
      getter? underline : Bool
      getter? strikethrough : Bool
      getter fg : Colorize::Color?
      getter bg : Colorize::Color?
      # Literal text prepended to each rendered line (e.g. "# ", "│ ", "  ").
      getter prefix : String?
      # Literal text appended after rendered content on the same line.
      getter suffix : String?

      def initialize(
        @bold : Bool = false,
        @italic : Bool = false,
        @dim : Bool = false,
        @underline : Bool = false,
        @strikethrough : Bool = false,
        @fg : Colorize::Color? = nil,
        @bg : Colorize::Color? = nil,
        @prefix : String? = nil,
        @suffix : String? = nil,
      )
      end

      # Returns the concatenated ANSI escape sequences for all active attributes.
      # Produces an empty string when no attributes are set (Style::NONE).
      def to_ansi : String
        parts = [] of String
        parts << ANSI::BOLD if @bold
        parts << ANSI::ITALIC if @italic
        parts << ANSI::DIM if @dim
        parts << ANSI::UNDERLINE if @underline
        parts << ANSI::STRIKETHROUGH if @strikethrough
        parts << ANSI.fg(@fg.not_nil!) if @fg
        parts << ANSI.bg(@bg.not_nil!) if @bg
        parts.join
      end

      # Returns true when no SGR attributes and no colors are set.
      # prefix/suffix are intentionally excluded: they affect layout, not color.
      def empty? : Bool
        !@bold && !@italic && !@dim && !@underline && !@strikethrough &&
          @fg.nil? && @bg.nil?
      end

      # Returns a new Style with `other`'s set attributes layered on top of self.
      # Bool flags: true wins (OR semantics — inline bold inside bold heading stays bold).
      # Optional fields (fg, bg, prefix, suffix): `other` wins when non-nil.
      def merge(other : Style) : Style
        Style.new(
          bold: @bold || other.bold?,
          italic: @italic || other.italic?,
          dim: @dim || other.dim?,
          underline: @underline || other.underline?,
          strikethrough: @strikethrough || other.strikethrough?,
          fg: other.fg || @fg,
          bg: other.bg || @bg,
          prefix: other.prefix || @prefix,
          suffix: other.suffix || @suffix
        )
      end

      # Value equality -- two Style instances are equal when all fields match.
      def ==(other : Style) : Bool
        @bold == other.bold? &&
          @italic == other.italic? &&
          @dim == other.dim? &&
          @underline == other.underline? &&
          @strikethrough == other.strikethrough? &&
          @fg == other.fg &&
          @bg == other.bg &&
          @prefix == other.prefix &&
          @suffix == other.suffix
      end

      # Canonical zero-value -- no styling applied. Immutable shared instance;
      # safe to share because Style exposes no mutation methods.
      NONE = new
    end
  end
end
