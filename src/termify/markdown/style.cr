require "../ansi"
require "./style/properties"

# -----
# Include ./style/* after defining Style
# -----

module Termify
  module Markdown
    # Base style -- SGR flags + colors. Parent of BlockStyle and InlineStyle.
    # Not constructed directly in normal use; instantiate a concrete subclass.
    #
    # to_ansi  -- concatenates active SGR sequences.
    # empty?   -- true when no SGR flags or colors are set.
    # merge    -- layers another style on top; bool flags OR,
    #             optional fields prefer other when non-nil.
    # ==       -- value equality across SGR + color fields.
    class Style
      include SGRProperties
      include ColorProperties

      def initialize(
        @bold : Bool = false,
        @italic : Bool = false,
        @dim : Bool = false,
        @underline : Bool = false,
        @strikethrough : Bool = false,
        @fg : Colorize::Color? = nil,
        @bg : Colorize::Color? = nil,
      )
      end

      # Returns concatenated ANSI escape sequences for all active attributes.
      # Produces an empty string when no attributes are set.
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
      # line_prefix/line_suffix (BlockStyle only) are excluded -- layout, not SGR.
      def empty? : Bool
        !@bold && !@italic && !@dim && !@underline && !@strikethrough &&
          @fg.nil? && @bg.nil?
      end

      # Returns a new Style with `other`'s attributes layered on top.
      # Bool flags: true wins (OR). Optional fields: other wins when non-nil.
      def merge(other : Style) : Style
        Style.new(
          bold: @bold || other.bold?,
          italic: @italic || other.italic?,
          dim: @dim || other.dim?,
          underline: @underline || other.underline?,
          strikethrough: @strikethrough || other.strikethrough?,
          fg: other.fg || @fg,
          bg: other.bg || @bg,
        )
      end

      # Value equality across SGR + color fields.
      def ==(other : Style) : Bool
        # Class equality checked by `Style#==` to preserve commutativity
        return false unless self.class == other.class

        @bold == other.bold? &&
          @italic == other.italic? &&
          @dim == other.dim? &&
          @underline == other.underline? &&
          @strikethrough == other.strikethrough? &&
          @fg == other.fg &&
          @bg == other.bg
      end
    end
  end
end

require "./style/*"
