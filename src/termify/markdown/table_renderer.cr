require "tablo"
require "colorize"

module Termify
  module Markdown
    # Renders a 2-D array of String cells as a terminal table via Tablo.
    # First row is treated as the header; remaining rows are data rows.
    class TableRenderer
      enum ColumnAlignment
        Left
        Right
        Middle
      end

      private def self.convert(align : ColumnAlignment?) : Tablo::Justify
        case align
        when .nil?, .left? then Tablo::Justify::Left
        when .right?       then Tablo::Justify::Right
        when .middle?      then Tablo::Justify::Center
        else                    Tablo::Justify::Left
        end
      end

      # Tablo doesn't handle escaped text when calculating
      # column widths and wrapping text.
      private def self.strip_escaped_codes(text)
        text.gsub(/\e\[[0-9;]*m/, "")
      end

      def self.render(rows : Array(Array(String)),
                      alignments : Array(ColumnAlignment),
                      io : IO, indent : Int32 = 0) : Nil
        return if rows.empty?

        max_cols = rows.max_of(&.size)
        header_cells = rows.first

        # Hard-coding border color; make this configurable for Table style
        # when we get the style system refactored
        border = Tablo::Border.new(:fancy,
          styler: ->(border_chars : String) { border_chars.colorize(:dark_gray).to_s })

        # Tablo doesn't work with escape codes; so we strip it out.
        table = Tablo::Table.new(rows[1..-1], border: border,
          row_divider_frequency: 1,
          header_styler: ->(content : String) { content.colorize.bold.to_s })
        max_cols.times do |i|
          align = convert(alignments[i])
          table.add_column(i,
            header_alignment: align,
            body_alignment: align,
            header: strip_escaped_codes(header_cells[i])) do |row|
            strip_escaped_codes(row[i]) || ""
          end
        end
        # Pack to min size first so we can check the width
        table.pack(autosize: true)
        # If it's really wide and not indented, re-pack to terminal width
        # Else if it's wider than 80, repack to 80
        # Else OK
        if table.total_table_width > 100 && indent == 0
          Tablo::Config.terminal_capped_width = true
          table.pack(autosize: true)
          Tablo::Config.terminal_capped_width = false
        elsif table.total_table_width > 80
          table.pack(80, autosize: true)
        end
        # Handle indent by prefixing each line of table render
        if indent > 0
          prefix = " " * indent
          table.to_s.each_line(chomp: false) do |line|
            io << prefix << line
          end
        else
          io << table
        end
        io.puts
      end
    end
  end
end
