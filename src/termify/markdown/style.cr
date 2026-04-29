require "../ansi"

module Termify
  module Markdown
    # Immutable value object describing the visual style for one markdown element.
    #
    # Attributes map directly to ANSI SGR flags plus optional fg/bg sequences
    # (any string produced by ANSI.*) and optional literal line_prefix/line_suffix strings
    # that bracket rendered text at the block level (e.g. "| " for blockquotes).
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
      # Literal text prepended to each rendered line (e.g. "# ", "| ", "  ").
      getter line_prefix : String?
      # Literal text appended after rendered content on the same line.
      getter line_suffix : String?

      def initialize(
        @bold : Bool = false,
        @italic : Bool = false,
        @dim : Bool = false,
        @underline : Bool = false,
        @strikethrough : Bool = false,
        @fg : Colorize::Color? = nil,
        @bg : Colorize::Color? = nil,
        @line_prefix : String? = nil,
        @line_suffix : String? = nil,
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
        if fore = @fg
          parts << ANSI.fg(fore)
        end
        if back = @bg
          parts << ANSI.bg(back)
        end
        parts.join
      end

      # Returns true when no SGR attributes and no colors are set.
      # line_prefix/line_suffix are intentionally excluded: they affect layout, not color.
      def empty? : Bool
        !@bold && !@italic && !@dim && !@underline && !@strikethrough &&
          @fg.nil? && @bg.nil?
      end

      # Returns a new Style with `other`'s set attributes layered on top of self.
      # Bool flags: true wins (OR semantics — inline bold inside bold heading stays bold).
      # Optional fields (fg, bg, line_prefix, line_suffix): `other` wins when non-nil.
      def merge(other : Style) : Style
        Style.new(
          bold: @bold || other.bold?,
          italic: @italic || other.italic?,
          dim: @dim || other.dim?,
          underline: @underline || other.underline?,
          strikethrough: @strikethrough || other.strikethrough?,
          fg: other.fg || @fg,
          bg: other.bg || @bg,
          line_prefix: other.line_prefix || @line_prefix,
          line_suffix: other.line_suffix || @line_suffix
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
          @line_prefix == other.line_prefix &&
          @line_suffix == other.line_suffix
      end

      # Canonical zero-value -- no styling applied. Immutable shared instance;
      # safe to share because Style exposes no mutation methods.
      NONE = new
    end
  end
end
