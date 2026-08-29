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

      # A cell's visible text and the styled runs that make it up. Tablo lays
      # out on `plain`; the runs are re-applied after it has wrapped.
      private record CellContent,
        plain : String,
        runs : Array(InlineRenderer::Run)

      # Renders *rows* of raw Markdown cell text. Inline markup is resolved
      # here rather than by the caller: tablo must measure and wrap unstyled
      # text, so styling is re-applied per wrapped line in the body styler.
      def self.render(rows : Array(Array(String)),
                      alignments : Array(ColumnAlignment),
                      io : IO,
                      inline : InlineRenderer,
                      style : Style,
                      indent : Int32 = 0) : Nil
        return if rows.empty?

        max_cols = rows.max_of(&.size)
        header_cells = rows.first
        body_rows = rows[1..-1]

        # Resolve every body cell once, up front, keyed by the coordinates
        # tablo will hand back to the styler.
        content = {} of {Int32, Int32} => CellContent
        body_rows.each_with_index do |row, row_index|
          max_cols.times do |col_index|
            runs = inline.runs(row[col_index]? || "", style)
            content[{row_index, col_index}] = CellContent.new(runs.map(&.text).join, runs)
          end
        end

        # Where in each cell the next wrapped line begins. Reset whenever
        # tablo reports line_index 0 for that cell.
        cursors = {} of {Int32, Int32} => Int32

        body_styler = ->(_value : Tablo::CellType, coords : Tablo::Cell::Data::Coords, text : String, line_index : Int32) {
          restyle(content, cursors, {coords.row_index, coords.column_index},
            text, line_index)
        }

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
          table = Tablo::Table.new(body_rows, border: border,
            row_divider_frequency: 1,
            body_styler: body_styler,
            header_styler: ->(header_text : String) { "#{ANSI::BOLD}#{header_text}#{ANSI::RESET}" })

          max_cols.times do |i|
            align = convert(alignments[i]?)
            table.add_column(i,
              header_alignment: align,
              body_alignment: align,
              header: inline.plain(header_cells[i]? || "", style)) do |_row, row_index|
              content[{row_index, i}]?.try(&.plain) || ""
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
          render_raw_table(rows, io, inline, style, indent)
        ensure
          Tablo::Config.styler_tty_only = was_tty_only
        end
        io.puts
      end

      # Re-applies a cell's styling to one wrapped line handed back by tablo.
      #
      # Tablo gives us the line's text but not where it sits in the cell, so
      # we track a cursor per cell and locate each line from there. Wrapping
      # is sequential, which makes the search unambiguous even when the same
      # word appears twice. A line we cannot place is returned unstyled rather
      # than styled in the wrong place -- that also covers the truncation
      # indicator, which arrives through this same callback.
      private def self.restyle(content : Hash({Int32, Int32}, CellContent),
                               cursors : Hash({Int32, Int32}, Int32),
                               key : {Int32, Int32},
                               text : String,
                               line_index : Int32) : String
        return text if text.empty?
        cell = content[key]?
        return text if cell.nil?

        cursors[key] = 0 if line_index.zero?
        from = cursors[key]? || 0
        at = cell.plain.index(text, from) || cell.plain.index(text)
        return text if at.nil?

        cursors[key] = at + text.size
        style_span(cell.runs, at, text.size)
      end

      # Emits the runs covering [from, from + len) of a cell, each carrying
      # its own sequence so the line stands alone.
      private def self.style_span(runs : Array(InlineRenderer::Run),
                                  from : Int32, len : Int32) : String
        finish = from + len
        String.build do |buf|
          offset = 0
          runs.each do |run|
            run_end = offset + run.text.size
            if run_end > from && offset < finish
              lo = {from, offset}.max - offset
              hi = {finish, run_end}.min - offset
              piece = run.text[lo...hi]
              buf << (run.ansi.empty? ? piece : "#{run.ansi}#{piece}#{ANSI::RESET}")
            end
            offset = run_end
          end
        end
      end

      # Tablo failed. Render the table as plain delimited lines. Cells are raw
      # Markdown, so inline markup is resolved here too; the divider is sized
      # on the visible text, never on the escape sequences.
      private def self.render_raw_table(rows : Array(Array(String)),
                                        io : IO,
                                        inline : InlineRenderer,
                                        style : Style,
                                        indent : Int32 = 0) : Nil
        prefix = indent > 0 ? " " * indent : ""
        rows.each_with_index do |row, i|
          io << prefix << row.map { |cell| inline.render(cell, style) }.join(" | ").strip
          io.puts
          next unless i.zero?
          # divider line after first row
          io << prefix
          row.each_with_index do |cell, col_ix|
            io << " | " if col_ix > 0
            io << " " * inline.plain(cell, style).size
          end
          io.puts
        end
      end
    end
  end
end
