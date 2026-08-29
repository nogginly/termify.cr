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

      # Border colour. Hard-coded for now; becomes a Table style property
      # when the style system is refactored.
      private BORDER_ANSI = ANSI.fg(Colorize::ColorANSI::DarkGray)

      # Above this width an unindented table is re-packed to the terminal
      # width rather than left to overflow.
      private TERMINAL_PACK_WIDTH = 100

      # Above this width a table is packed down to it. Wide enough to be
      # useful, narrow enough to stay readable in a split pane.
      private COMFORTABLE_WIDTH = 80

      # SGR escape sequences, stripped before handing text to tablo.
      private STRIP_SGR_RE = /\e\[[0-9;]*m/

      # Tablo doesn't handle escaped text when calculating
      # column widths and wrapping text.
      private def self.strip_escaped_codes(text)
        text.gsub(STRIP_SGR_RE, "") if text
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
          styler: ->(border_chars : String) { "#{BORDER_ANSI}#{border_chars}#{ANSI::RESET}" })

        # Tablo suppresses stylers unless STDOUT is a tty. We write to a
        # caller-supplied IO, so that decision is not tablo's to make -- the
        # caller chose the destination. Restore the flag afterwards so we do
        # not change behaviour for a host application also using tablo.
        was_tty_only = Tablo::Config.styler_tty_only?
        Tablo::Config.styler_tty_only = false
        begin
          # Safely try and render table
          # Tablo doesn't work with escape codes; so we strip it out.
          table = Tablo::Table.new(rows[1..-1], border: border,
            row_divider_frequency: 1,
            header_styler: ->(content : String) { "#{ANSI::BOLD}#{content}#{ANSI::RESET}" })

          max_cols.times do |i|
            align = convert(alignments[i]?)
            table.add_column(i,
              header_alignment: align,
              body_alignment: align,
              header: strip_escaped_codes(header_cells[i]?) || "") do |row|
              strip_escaped_codes(row[i]?) || ""
            end
          end
          # Pack to min size first so we can check the width
          table.pack(autosize: true)
          # If it's really wide and not indented, re-pack to terminal width
          # Else if it's wider than the comfortable width, repack to that
          # Else OK
          if table.total_table_width > TERMINAL_PACK_WIDTH && indent == 0
            begin
              # Global config; restore it even if pack raises, or every later
              # table in the process inherits the capped width.
              Tablo::Config.terminal_capped_width = true
              table.pack(autosize: true)
            ensure
              Tablo::Config.terminal_capped_width = false
            end
          elsif table.total_table_width > COMFORTABLE_WIDTH
            table.pack(COMFORTABLE_WIDTH, autosize: true)
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
        rescue
          # Tablo failed. Render table raw
          render_raw_table(rows, io, indent)
        ensure
          Tablo::Config.styler_tty_only = was_tty_only
        end
        io.puts
      end

      private def self.render_raw_table(rows : Array(Array(String)),
                                        io : IO, indent : Int32 = 0) : Nil
        # Tablo failed. Render table raw
        prefix = indent > 0 ? " " * indent : ""
        rows.each_with_index do |row, i|
          io << prefix << row.join(" | ").strip
          io.puts
          if i.zero?
            # divider line after first row
            io << prefix
            row.each_with_index do |col, col_ix|
              io << " | " if col_ix > 0
              io << " " * col.size
            end
            io.puts
          end
        end
      end
    end
  end
end
