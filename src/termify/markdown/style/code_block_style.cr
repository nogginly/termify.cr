require "../style"

module Termify
  module Markdown
    # Style for code blocks. Extends BlockStyle with code-specific properties.
    # Currently adds line_number_format: a sprintf format string for line number
    # gutters (e.g. "%3d | "). nil means no line numbers.
    class CodeBlockStyle < BlockStyle
      getter line_number_format : String?

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
      )
        super(bold: bold, italic: italic, dim: dim, underline: underline,
          strikethrough: strikethrough, fg: fg, bg: bg,
          line_prefix: line_prefix, line_suffix: line_suffix,
          newline_before: newline_before, newline_after: newline_after)
      end

      # merge returns CodeBlockStyle, layering other on top.
      # line_number_format: other wins when non-nil.
      # ameba:disable Metrics/CyclomaticComplexity
      def merge(other : Style) : CodeBlockStyle
        other_line_prefix = other_line_suffix = nil
        other_newline_before = other_newline_after = false
        other_line_number_format = nil
        if other.is_a?(BlockStyle)
          other_line_prefix = other.line_prefix
          other_line_suffix = other.line_suffix
          other_newline_before = other.newline_before?
          other_newline_after = other.newline_after?
        end
        other_line_number_format = other.line_number_format if other.is_a?(CodeBlockStyle)
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
        )
      end

      # Equality includes all fields; always false vs non-CodeBlockStyle.
      def ==(other : Style) : Bool
        super && @line_number_format == (other.is_a?(CodeBlockStyle) ? other.line_number_format : nil)
      end

      # Canonical zero-value for code block styles.
      NONE = new
    end
  end
end
