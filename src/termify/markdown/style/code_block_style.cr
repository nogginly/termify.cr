require "../style"

module Termify
  module Markdown
    # Style for code blocks. Extends BlockStyle with code-specific properties.
    # line_number_format: sprintf format string for gutters (e.g. "%3d | ").
    #   nil means no line numbers.
    # gutter_style: InlineStyle applied to the gutter only. nil inherits the
    #   block style so the gutter matches the code content visually.
    class CodeBlockStyle < BlockStyle
      getter line_number_format : String?
      getter gutter_style : InlineStyle?

      def initialize(
        bold : Bool = false,
        italic : Bool = false,
        dim : Bool = false,
        underline : Bool = false,
        strikethrough : Bool = false,
        fg : ANSI::Color? = nil,
        bg : ANSI::Color? = nil,
        line_prefix : String? = nil,
        line_suffix : String? = nil,
        newline_before : Bool = false,
        newline_after : Bool = false,
        @line_number_format : String? = nil,
        @gutter_style : InlineStyle? = nil,
      )
        super(bold: bold, italic: italic, dim: dim, underline: underline,
          strikethrough: strikethrough, fg: fg, bg: bg,
          line_prefix: line_prefix, line_suffix: line_suffix,
          newline_before: newline_before, newline_after: newline_after)
      end

      # merge returns CodeBlockStyle, layering other on top.
      # line_number_format and gutter_style: other wins when non-nil.
      # ameba:disable Metrics/CyclomaticComplexity
      def merge(other : Style) : CodeBlockStyle
        other_line_prefix = other_line_suffix = nil
        other_newline_before = other_newline_after = false
        other_line_number_format = nil
        other_gutter_style = nil
        if other.is_a?(BlockStyle)
          other_line_prefix = other.line_prefix
          other_line_suffix = other.line_suffix
          other_newline_before = other.newline_before?
          other_newline_after = other.newline_after?
        end
        if other.is_a?(CodeBlockStyle)
          other_line_number_format = other.line_number_format
          other_gutter_style = other.gutter_style
        end
        CodeBlockStyle.new(
          bold: bold? || other.bold?,
          italic: italic? || other.italic?,
          dim: dim? || other.dim?,
          underline: underline? || other.underline?,
          strikethrough: strikethrough? || other.strikethrough?,
          fg: other.fg || fg,
          bg: other.bg || bg,
          line_prefix: other_line_prefix || line_prefix,
          line_suffix: other_line_suffix || line_suffix,
          newline_before: newline_before? || other_newline_before,
          newline_after: newline_after? || other_newline_after,
          line_number_format: other_line_number_format || @line_number_format,
          gutter_style: other_gutter_style || @gutter_style,
        )
      end

      # Equality includes all fields; always false vs non-CodeBlockStyle.
      def ==(other : Style) : Bool
        return false unless super
        return false unless other.is_a?(CodeBlockStyle)
        @line_number_format == other.line_number_format &&
          @gutter_style == other.gutter_style
      end

      # Canonical zero-value for code block styles.
      NONE = new
    end
  end
end
