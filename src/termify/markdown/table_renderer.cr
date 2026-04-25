require "tallboy"

module Termify
  module Markdown
    # Renders a 2-D array of String cells as a terminal table via tallboy.
    # First row is treated as the header; remaining rows are data rows.
    # Isolated so the tallboy dependency can be swapped without touching Renderer.
    #
    # NOTE: the Tallboy DSL calls below (`Tallboy.table`, `header`, `row`)
    # reflect the library's documented API -- verify against your installed
    # version if compilation fails here.
    class TableRenderer
      enum ColumnAlignment
        Left
        Right
        Middle

        def to_tallboy : Tallboy::AlignValue
          case self
          when .left?   then Tallboy::Alignment::Left
          when .right?  then Tallboy::Alignment::Right
          when .middle? then Tallboy::Alignment::Center
          else               Tallboy::AlignOption::Auto
          end
        end
      end

      private def self.convert(align : ColumnAlignment?) : Tallboy::AlignValue
        align.try(&.to_tallboy) || Tallboy::Alignment::Center
      end

      def self.render(rows : Array(Array(String)), alignments : Array(ColumnAlignment), io : IO) : Nil
        return if rows.empty?

        max_cols = rows.max_of(&.size)

        header_cells = rows.first
        data_rows = rows[1..]
        table = Tallboy.table do
          header do
            header_cells.each_with_index do |label, i|
              # cell label, align: :left
              cell label, align: convert(alignments[i]?)
            end
            (max_cols - header_cells.size).times do
              cell ""
            end
          end
          data_rows.each do |cells|
            row do
              cells.each do |value|
                cell value
              end
              (max_cols - cells.size).times do
                cell ""
              end
            end
          end
        end
        io << table
      end
    end
  end
end
