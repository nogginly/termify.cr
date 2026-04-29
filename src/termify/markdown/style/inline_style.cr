require "../style"

module Termify
  module Markdown
    # Style for inline elements. No additional fields beyond Style.
    # merge returns InlineStyle.
    class InlineStyle < Style
      def merge(other : Style) : InlineStyle
        InlineStyle.new(
          bold: bold? || other.bold?,
          italic: italic? || other.italic?,
          dim: dim? || other.dim?,
          underline: underline? || other.underline?,
          strikethrough: strikethrough? || other.strikethrough?,
          fg: other.fg || fg,
          bg: other.bg || bg,
        )
      end

      # Canonical zero-value for inline styles.
      NONE = new
    end
  end
end
