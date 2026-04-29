require "../style"

module Termify
  module Markdown
    # Style for block elements. Adds line_prefix and line_suffix.
    # merge returns BlockStyle; == includes layout fields.
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
      )
        super(bold: bold, italic: italic, dim: dim, underline: underline,
          strikethrough: strikethrough, fg: fg, bg: bg)
      end

      # merge picks up line_prefix/line_suffix from other only when other is a BlockStyle.
      # ameba:disable Metrics/CyclomaticComplexity
      def merge(other : Style) : BlockStyle
        other_prefix = other_suffix = nil
        if other.is_a?(BlockStyle)
          other_prefix = other.line_prefix
          other_suffix = other.line_suffix
        end
        BlockStyle.new(
          bold: bold? || other.bold?,
          italic: italic? || other.italic?,
          dim: dim? || other.dim?,
          underline: underline? || other.underline?,
          strikethrough: strikethrough? || other.strikethrough?,
          fg: other.fg || fg,
          bg: other.bg || bg,
          line_prefix: other_prefix || @line_prefix,
          line_suffix: other_suffix || @line_suffix,
        )
      end

      # Equality includes line_prefix and line_suffix; always false vs non-BlockStyle.
      def ==(other : Style) : Bool
        # Class equality checked by `Style#==` to preserve commutativity
        super && @line_prefix == other.line_prefix && @line_suffix == other.line_suffix
      end

      # Canonical zero-value for block styles.
      NONE = new
    end
  end
end
