require "../style"

module Termify
  module Markdown
    # Style for block elements. Adds line_prefix, line_suffix, newline_before, newline_after.
    # merge returns BlockStyle; == includes all layout fields.
    class BlockStyle < Style
      include BlockLayoutProperties

      def initialize(
        bold : Bool = false,
        italic : Bool = false,
        dim : Bool = false,
        underline : Bool = false,
        strikethrough : Bool = false,
        fg : Colorize::Color? = nil,
        bg : Colorize::Color? = nil,
        @line_prefix : String? = nil,
        @line_suffix : String? = nil,
        @newline_before : Bool = false,
        @newline_after : Bool = false,
      )
        super(bold: bold, italic: italic, dim: dim, underline: underline,
          strikethrough: strikethrough, fg: fg, bg: bg)
      end

      # merge picks up layout fields from other only when other is a BlockStyle.
      # Bool layout flags use OR so either side can request spacing.
      # ameba:disable Metrics/CyclomaticComplexity
      def merge(other : Style) : BlockStyle
        other_line_prefix = other_line_suffix = nil
        other_newline_before = other_newline_after = false
        if other.is_a?(BlockStyle)
          other_line_prefix = other.line_prefix
          other_line_suffix = other.line_suffix
          other_newline_before = other.newline_before?
          other_newline_after = other.newline_after?
        end
        BlockStyle.new(
          bold: bold? || other.bold?,
          italic: italic? || other.italic?,
          dim: dim? || other.dim?,
          underline: underline? || other.underline?,
          strikethrough: strikethrough? || other.strikethrough?,
          fg: other.fg || fg,
          bg: other.bg || bg,
          line_prefix: other_line_prefix || @line_prefix,
          line_suffix: other_line_suffix || @line_suffix,
          newline_before: @newline_before || other_newline_before,
          newline_after: @newline_after || other_newline_after,
        )
      end

      # Equality includes all layout fields; always false vs non-BlockStyle.
      def ==(other : Style) : Bool
        # Class equality checked by `Style#==` to preserve commutativity
        super &&
          @line_prefix == other.line_prefix &&
          @line_suffix == other.line_suffix &&
          @newline_before == other.newline_before? &&
          @newline_after == other.newline_after?
      end

      # Canonical zero-value for block styles.
      NONE = new
    end
  end
end
