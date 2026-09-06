require "./style_sheet"
require "./gather_event"
require "./table_renderer"
require "./code_renderer"
require "./blockquote_io"
require "./inline_renderer"

module Termify
  module Markdown
    enum BlockMode
      Normal
      CodeFence
      Table
    end

    # Streaming Markdown-to-ANSI renderer.
    #
    # Feed arbitrary chunks of Markdown text via #feed (or via the IO interface);
    # the renderer emits styled ANSI lines to *io* as soon as complete lines are
    # available. Call #close when the input stream is exhausted to flush any
    # remainder.
    #
    # Data flow:
    #   feed(chunk) -> @buf << chunk -> flush_complete_lines
    #                                     scan for \n
    #                                     process_line(each complete line)
    #                                     keep remainder in @buf
    #   close       -> flush_complete_lines -> process_line(remainder) if any
    #
    # IO contract
    # -----------
    # Renderer inherits IO for composability: any IO-accepting API (puts, <<,
    # pipe, etc.) can target a Renderer directly. write(Bytes) is the required
    # implementation point; it decodes the slice as UTF-8 and delegates to feed.
    # Caller guarantees valid UTF-8; no BOM handling is performed.
    # read(Bytes) always raises -- the renderer is write-only.
    # The renderer never closes @io; the caller owns the output IO lifecycle.

    class Renderer < IO
      # -- patterns ----------------------------------------------------------
      private HEADING         = /^([#]{1,6}) (.*)/
      private UNORDERED_LIST  = /^\s*[-*+] (.*)/
      private ORDERED_LIST    = /^\s*(\d+)[.)] (.*)/
      private HORIZONTAL_RULE = /^\s*(-{3,}|\*{3,}|_{3,})\s*$/
      private BULLETS         = ["*", "+", "-"] # asterisk, plus, hyphen
      private BLOCK_HTML      = /^\s*<[^>]+>\s*$/

      # A candidate table row -- any line carrying at least one pipe. Two kinds
      # of row syntax are accepted:
      #     | value | value ... |
      #       value | value | ...
      # This test is deliberately lax. A candidate is not treated as a table
      # until the following line is confirmed to be a delimiter row, so prose
      # containing a pipe (e.g. "if x || y") is released as a paragraph.
      private TABLE_ROW = /\|/

      # A table delimiter row: pipe-separated cells of dashes with optional
      # alignment colons and nothing else. Anchored at both ends so prose
      # cannot match.
      #     | ----- | -----: | ... |
      #       ----- | :----: | ...
      # A bare "---" matches this shape but is a horizontal rule, so callers
      # must use `table_separator?`, which also requires a pipe.
      private TABLE_SEPARATOR = /\A\s*\|?\s*:?-+:?\s*(?:\|\s*:?-+:?\s*)*\|?\s*\z/

      getter stylesheet : Stylesheet
      getter io : IO

      # -- IO abstract interface ---------------------------------------------
      # Decodes `slice` as UTF-8 Markdown and feeds it into the renderer.
      # Caller guarantees valid UTF-8.
      def write(slice : Bytes) : Nil
        feed(String.new(slice))
      end

      # Renderer is write-only; reading always raises.
      def read(slice : Bytes) : Int32
        raise IO::Error.new("Renderer is write-only")
      end

      # -- lifecycle ---------------------------------------------------------
      def initialize(
        @io : IO,
        @stylesheet : Stylesheet = Stylesheet.default,
        @on_gather : Proc(GatherEvent, Nil)? = nil,
      )
        @inline = InlineRenderer.new(@stylesheet)
        @closed = false
        @buf = String::Builder.new
        @block_mode = BlockMode::Normal
        @fence_marker = ""
        @fence_indent = 0
        @table_rows = [] of Array(String)
        @table_col_alignments = [] of TableRenderer::ColumnAlignment

        # Non-nil while content is being held back. Drives the guarantee that
        # a Started event is always answered by a Finished one.
        @gathering = nil.as(GatherKind?)
        @gather_units = 0

        # A row that looks like a table header, held back for one line while
        # we wait to see whether a delimiter row follows. See
        # `#resolve_table_candidate`.
        @table_candidate = nil.as(String?)
        @code_renderer = nil.as(CodeRenderer?)
        @quote_renderer = nil.as(Renderer?)
        @list_stack = [] of NamedTuple(indent: Int32, ordered: Bool, counter: Int32, content_indent: Int32)
        @list_pending_blank = false
        @current_block = nil.as(BlockElement?)

        # Need to track if current line is empty so we can
        # ensure blank lines don't accumulate, and ensure that
        # block newline-based margin (via newline_before/newline_after)
        # merging works properly with blank lines.
        @current_line_empty = false
      end

      # Accepts the next chunk of Markdown. May be any size -- a single byte
      # up to the entire document. Raises if called after #close.
      def feed(chunk : String) : Nil
        raise "Renderer is closed" if @closed
        @buf << chunk
        flush_complete_lines if chunk.includes?('\n')
      end

      # Resets the renderer (see `#reset`) and marks the renderer closed.
      def close : Nil
        return if @closed
        @closed = true
        reset
      end

      def closed? : Bool
        @closed
      end

      # Flushes any buffered content AND resets the renderer, closing off
      # any block/list/blockquote/table states. The ensure is what makes the
      # Started/Finished pairing a guarantee rather than an intention: it
      # covers close, an early reset, and an exception raised mid-table.
      def reset
        flush_complete_lines
        remainder = @buf.to_s
        @buf = String::Builder.new
        process_line(remainder) unless remainder.empty?
        close_quote_renderer
        release_table_candidate
        flush_table if @block_mode.table?
        close_block(nil)
      ensure
        gather_finished
      end

      # -- private -----------------------------------------------------------
      # Marks the start of held-back content. A second call while already
      # gathering is ignored, so nesting cannot open a second pair.
      private def gather_started(kind : GatherKind) : Nil
        return if @gathering
        @gathering = kind
        @gather_units = 0
        emit_gather(GatherPhase::Started, kind)
      end

      # Reports one more unit of held-back content: a table row, a code line.
      private def gather_progressed : Nil
        kind = @gathering
        return if kind.nil?
        @gather_units += 1
        emit_gather(GatherPhase::Progressed, kind)
      end

      # Closes the pair. Safe to call when not gathering, which is what lets
      # reset call it unconditionally from an ensure.
      private def gather_finished : Nil
        kind = @gathering
        return if kind.nil?
        @gathering = nil
        emit_gather(GatherPhase::Finished, kind)
      end

      # The handler is presentation code supplied by the caller. Its failure
      # must not abort a render, and must not stop the Finished event that
      # tells the caller to take its spinner down.
      private def emit_gather(phase : GatherPhase, kind : GatherKind) : Nil
        handler = @on_gather
        return if handler.nil?
        handler.call(GatherEvent.new(phase, kind, @gather_units))
      rescue
        nil
      end

      # Drains every complete (newline-terminated) line from @buf, passing each
      # to process_line. Leaves the trailing partial line (possibly empty) in @buf.
      private def flush_complete_lines : Nil
        content = @buf.to_s
        @buf = String::Builder.new
        content.each_line(chomp: false) do |line|
          if line.ends_with?('\n')
            process_line(line.chomp)
          else
            @buf << line
          end
        end
      end

      # Dispatches one logical line to the appropriate block handler.
      private def process_line(line : String) : Nil
        return if process_fence_line(line)
        # A held candidate must be resolved before any other handler sees the
        # line, since only the immediately following line can confirm it.
        return if @table_candidate && resolve_table_candidate(line)
        unless @list_stack.empty?
          return if handle_list_line(line)
        end
        # An open table must also see the line before quote routing. Only the
        # row check can consume it; anything else flushes the table and falls
        # through, so a quote following a table is still routed correctly.
        return if @block_mode.table? && process_table_line(line)
        return if process_quote_line(line)
        return if process_table_line(line)
        dispatch_block(line)
      end

      # Handles a line while in CodeFence mode. Returns true if consumed.
      # When inside a list, strips the item's content indent before checking
      # the fence marker so indented fences work correctly.
      private def process_fence_line(line : String) : Bool
        return false unless @block_mode.code_fence?
        # Only strip @fence_indent spaces if the line actually starts with them.
        # Body lines in a top-level fence have no indent; this avoids slicing
        # into content when a fence opens with leading spaces.
        stripped = (@fence_indent > 0 && line.starts_with?(" " * @fence_indent)) ? line[@fence_indent..] : line
        if stripped.starts_with?(@fence_marker)
          # Before close: closing the code renderer is what emits a buffered
          # highlighted body.
          gather_finished
          @code_renderer.try(&.close)
          @code_renderer = nil
          @block_mode = BlockMode::Normal
        else
          # After open_block, which emits the block's top margin. Starting the
          # gather before it would put a newline between Started and Finished,
          # under a caller's spinner. Only the code renderer knows whether it
          # holds lines back: a theme is not enough, since a language with no
          # lexer streams as plain text.
          open_block(BlockElement::CodeBlock)
          gather_started(GatherKind::CodeBlock) if @code_renderer.try(&.buffering?)
          gather_progressed
          @code_renderer.try(&.feed(stripped))
          @current_line_empty = false
        end
        true
      end

      # Handles a line while in Table mode, or detects a new table. Returns
      # true if the line was consumed, false to fall through to dispatch_block.
      private def process_table_line(line : String) : Bool
        if @block_mode.table?
          if table_row?(line)
            buffer_table_row(line)
            return true
          else
            flush_table
            return false
          end
        elsif table_row?(line)
          # Hold the row back rather than committing to a table. Only a
          # delimiter row on the next line confirms it.
          @table_candidate = line
          return true
        end
        false
      end

      # True if *line* could be a table row -- it carries at least one pipe
      # acting as a delimiter. Pipes inside a code span or escaped as "\|" are
      # content, so they do not raise a candidate. Uses the same rules as
      # `#split_cells`, so detection and splitting cannot disagree.
      private def table_row?(line : String) : Bool
        return false unless TABLE_ROW.matches?(line)
        split_cells(line).size > 1
      end

      # True if *line* is a table delimiter row. Requires a pipe as well as
      # the dashes-and-colons shape, so a bare "---" stays a horizontal rule.
      private def table_separator?(line : String) : Bool
        line.includes?('|') && TABLE_SEPARATOR.matches?(line)
      end

      # Decides the fate of the held candidate row now that the next line is
      # known. Returns true if *line* was consumed.
      #
      #   delimiter row  -> promote both to a table, consume the line
      #   anything else  -> release the candidate as a normal block; the line
      #                     itself becomes a fresh candidate if it too carries
      #                     a pipe, otherwise it falls through for dispatch
      private def resolve_table_candidate(line : String) : Bool
        candidate = @table_candidate
        return false if candidate.nil?
        @table_candidate = nil

        if table_separator?(line)
          @block_mode = BlockMode::Table
          gather_started(GatherKind::Table)
          buffer_table_row(candidate)
          buffer_table_row(line)
          return true
        end

        dispatch_block(candidate)
        if table_row?(line)
          @table_candidate = line
          true
        else
          false
        end
      end

      # Emits a held candidate as a normal block. Called when the input ends
      # before a delimiter row could confirm it.
      private def release_table_candidate : Nil
        if candidate = @table_candidate
          @table_candidate = nil
          dispatch_block(candidate)
        end
      end

      # Parses and buffers one table row; silently drops separator rows.
      # Splits a table row into cells on pipes that act as delimiters. A pipe
      # inside a code span, or escaped as "\|", is cell content rather than a
      # separator; the escape is consumed so the cell holds a literal pipe.
      #
      # Backticks only protect a pipe when they pair up. An odd count means an
      # unmatched backtick, which Markdown treats as a literal, so protection
      # is skipped rather than swallowing the rest of the row into one cell.
      private def split_cells(line : String) : Array(String)
        protect_code = line.count('`').even?
        cells = [] of String
        cell = String::Builder.new
        in_code = false
        chars = line.chars
        i = 0
        while i < chars.size
          ch = chars[i]
          if ch == '\\' && chars[i + 1]? == '|'
            cell << '|'
            i += 2
            next
          end
          in_code = !in_code if ch == '`' && protect_code
          if ch == '|' && !in_code
            cells << cell.to_s
            cell = String::Builder.new
          else
            cell << ch
          end
          i += 1
        end
        cells << cell.to_s
        cells
      end

      # Drops the empty cells produced by leading and trailing separators.
      private def trim_edge_cells(cells : Array(String), line : String) : Array(String)
        cells = cells[1..] if cells.size > 1 && line.starts_with?('|')
        if cells.size > 1 && line.ends_with?('|') && !line.ends_with?("\\|")
          cells = cells[0..-2]
        end
        cells
      end

      private def buffer_table_row(line : String) : Nil
        gather_progressed
        cells = trim_edge_cells(split_cells(line), line).map(&.strip)

        if table_separator?(line)
          @table_col_alignments = cells.map do |cell|
            case cell
            when .ends_with?(':') then TableRenderer::ColumnAlignment::Right
            when .includes?(':')  then TableRenderer::ColumnAlignment::Middle
            else                       TableRenderer::ColumnAlignment::Left
            end
          end
        else
          # Raw cell text. Inline markup is resolved by TableRenderer, which
          # needs unstyled text to lay out on and applies styling after
          # wrapping. Rendering it here would only have to be undone.
          @table_rows << cells
        end
      end

      # Returns leading spaces matching current list content indent, or "".
      private def list_visual_indent : String
        @list_stack.empty? ? "" : " " * @list_stack.last[:content_indent]
      end

      # Renders buffered rows via TableRenderer and resets table state.
      # gather_finished comes first, before any byte is written: the caller
      # needs its spinner down before the table lands on top of it.
      private def flush_table : Nil
        gather_finished
        close_block(nil)
        unless @table_rows.empty?
          indent = @list_stack.empty? ? 0 : @list_stack.last[:content_indent]
          TableRenderer.render(@table_rows, @table_col_alignments, @io,
            @inline, @stylesheet[BlockElement::Table], indent)
          @current_line_empty = false
        end
        @table_rows.clear
        @block_mode = BlockMode::Normal
      end

      private def fence_start?(line : String) : Bool
        stripped = line.lstrip
        return false if line.size - stripped.size > 3
        stripped.starts_with?("```") || stripped.starts_with?("~~~")
      end

      # Handles a line that may belong to a blockquote. Returns true if consumed.
      # A > prefix routes to the child renderer; a blank line is forwarded to
      # the child if one is active; any other line closes the child and returns
      # false so normal dispatch can proceed.
      private def process_quote_line(line : String) : Bool
        if line.starts_with?("> ")
          open_quote_renderer
          @quote_renderer.try(&.feed(line[2..] + "\n"))
          true
        elsif line.starts_with?(">")
          open_quote_renderer
          @quote_renderer.try(&.feed(line[1..] + "\n"))
          true
        else
          # Blank lines and non-quote lines both close any deeper nesting and
          # fall through. This ensures blank lines get prefix decoration at the
          # correct depth rather than being forwarded one level too deep.
          close_quote_renderer
          false
        end
      end

      # Opens a child Renderer writing through a BlockquoteIO prefix wrapper.
      # Idempotent -- a second call while the child is active is a no-op.
      private def open_quote_renderer : Nil
        return if @quote_renderer
        open_block(BlockElement::Blockquote)
        style = @stylesheet[BlockElement::Blockquote]
        ansi = style.to_ansi
        prefix = style.line_prefix || ""
        # Emit EL+RESET suffix only on the outermost BlockquoteIO.
        # Inner BIOs must use an empty suffix so the bg color stays active
        # past their \n and the outermost EL fires while bg is still set.
        # An inner RESET before the outer EL would clear the bg and cause
        # the outer EL to fill with the terminal default instead of the bg color.
        is_nested = @io.is_a?(BlockquoteIO)
        suffix = (style.bg && !ansi.empty? && !is_nested) ? ANSI::ERASE_LINE + ANSI::RESET : ""
        wrapped_io = BlockquoteIO.new(@io, list_visual_indent + ansi + prefix, suffix)
        @quote_renderer = Renderer.new(wrapped_io, @stylesheet, @on_gather)
      end

      # True when the last line written was blank. A parent renderer reads this
      # from its closing child so margin accounting survives the handover.
      protected getter? current_line_empty : Bool

      # Closes and flushes the child renderer, syncing blank-line state back
      # to the parent so margin logic stays correct for the next block.
      private def close_quote_renderer : Nil
        if r = @quote_renderer
          r.close
          @quote_renderer = nil
          @current_line_empty = r.current_line_empty?
        end
      end

      private def dispatch_block(line : String) : Nil
        if m = line.match(HEADING)
          emit_styled(heading_element(m[1].size), m[2])
        elsif fence_start?(line)
          fenced = line.lstrip
          @fence_marker = fenced[0, 3]
          @fence_indent = line.size - fenced.size
          language = fenced[3..].strip
          @code_renderer = CodeRenderer.new(
            language,
            @stylesheet.code_block_style,
            @io,
            list_visual_indent
          )
          @block_mode = BlockMode::CodeFence
        elsif horizontal_rule?(line)
          emit_styled(BlockElement::HorizontalRule, line)
        elsif list_line?(line)
          process_list_item(line)
        elsif BLOCK_HTML.matches?(line)
          emit_raw(BlockElement::BlockHtml, line.strip)
          @current_line_empty = false
        else
          emit_styled(BlockElement::Paragraph, line)
        end
      end

      # Called when the first line of a new semantic block arrives.
      # Closes the previous block (emitting newline_after if set), then
      # emits newline_before for the incoming block, OR-collapsed with
      # newline_after of the outgoing block so at most one blank line appears.
      private def open_block(element : BlockElement) : Nil
        return if @current_block == element
        unless @current_line_empty
          incoming = @stylesheet[element]
          outgoing_after = if prev = @current_block
                             @stylesheet[prev].newline_after?
                           else
                             false
                           end
          if outgoing_after || incoming.newline_before?
            @current_line_empty = true # sometimes we write an empty line, so remember that
            @io << '\n'
          end
        end
        @current_block = element
      end

      # Called when the current block is known to be finished (blank line,
      # close, exit_list, flush_table). Resets tracking; newline_after is
      # handled by open_block for the next block via OR-collapse, or by
      # close when the document ends.
      private def close_block(element : BlockElement?) : Nil
        if element.nil? && (prev = @current_block) && !@current_line_empty
          if @stylesheet[prev].newline_after?
            @current_line_empty = true # sometimes we write an empty line, so remember that
            @io << '\n'
          end
        end
        @current_block = element
      end

      private def emit_styled(element : BlockElement, text : String, io = @io, chomp = false) : Nil
        open_block(element) if io.same?(@io)

        return if text.empty? && @current_line_empty

        style = @stylesheet[element]
        ansi = style.to_ansi
        prefix = style.line_prefix || ""
        erase = (style.bg && !ansi.empty?) ? ANSI::ERASE_LINE : ""
        reset = ansi.empty? ? "" : ANSI::RESET
        list_indent = io.same?(@io) ? list_visual_indent : ""
        io << ansi << list_indent << prefix << @inline.render(text, style) << erase << reset << style.line_suffix
        io << '\n' unless chomp

        # sometimes we write an empty line, so remember that -- but only when
        # writing to our own IO. Table cells render into a String::Builder and
        # must not disturb the parent's blank line accounting.
        @current_line_empty = text.empty? if io.same?(@io)
      end

      # Emits *text* verbatim -- no inline parsing. Used for block HTML.
      private def emit_raw(element : BlockElement, text : String) : Nil
        open_block(element)
        style = @stylesheet[element]
        ansi = style.to_ansi
        prefix = style.line_prefix || ""
        erase = (style.bg && !ansi.empty?) ? ANSI::ERASE_LINE : ""
        reset = ansi.empty? ? "" : ANSI::RESET
        @io << ansi << list_visual_indent << prefix << text << erase << reset << '\n'
      end

      # -- block helpers -----------------------------------------------------
      private def heading_element(level : Int) : BlockElement
        case level
        when 1 then BlockElement::H1
        when 2 then BlockElement::H2
        when 3 then BlockElement::H3
        when 4 then BlockElement::H4
        when 5 then BlockElement::H5
        else        BlockElement::H6
        end
      end

      private def horizontal_rule?(line : String) : Bool
        !!(line =~ HORIZONTAL_RULE)
      end

      # -- list helpers -------------------------------------------------------

      # Returns true if *line* is an unordered or ordered list item.
      private def list_line?(line : String) : Bool
        UNORDERED_LIST.matches?(line) || ORDERED_LIST.matches?(line)
      end

      # Clears list nesting state. Called on any non-continuation, non-list line.
      # Blank lines within a list item are swallowed (loose list termination deferred).
      private def exit_list : Nil
        close_block(nil)
        @list_stack.clear
        @list_pending_blank = false
      end

      # Handles a line while a list is active. Returns true if consumed; false
      # if the list was exited and the line needs normal dispatch.
      private def handle_list_line(line : String) : Bool
        if line.empty?
          @list_pending_blank = true
          return true
        end

        pending = @list_pending_blank
        @list_pending_blank = false

        if list_line?(line)
          flush_table if @block_mode.table?
          process_list_item(line)
          true
        elsif list_continuation?(line)
          indent = line.size - line.lstrip.size
          dispatch_continuation(line.lstrip)
          # If the continuation opened a code fence, the line was already
          # lstripped before dispatch so @fence_indent was set to 0. Patch it
          # with the actual indent so process_fence_line can match the closing
          # marker correctly.
          @fence_indent = indent if @block_mode.code_fence?
          true
        else
          flush_table if @block_mode.table?
          exit_list
          emit_pending_blank if pending
          false
        end
      end

      # Emits the blank line deferred from inside a list. Skips it when the
      # output already sits on a blank -- exit_list may have emitted one via
      # close_block -- and records it either way, so the open_block that
      # follows does not add a second.
      private def emit_pending_blank : Nil
        return if @current_line_empty

        @current_line_empty = true
        @io << '\n'
      end

      # Returns true if *line* has any positive indentation, making it a
      # continuation block of the current list item. list_line? is checked
      # first so actual list items are never misidentified as continuations.
      private def list_continuation?(line : String) : Bool
        line.size - line.lstrip.size > 0
      end

      # Dispatches a continuation line (already de-indented) through the normal
      # table and block pipeline, bypassing the list check.
      private def dispatch_continuation(line : String) : Nil
        return if process_quote_line(line)
        return if process_table_line(line)
        dispatch_block(line)
      end

      # Emits one item: parses the line, updates nesting, renders the content.
      private def process_list_item(line : String) : Nil
        indent, ordered, content, content_indent, number = parse_list_line(line)
        update_list_stack(indent, ordered, content_indent, number)
        emit_list_item(content, list_item_prefix(ordered))
      end

      # Parses indent, type, content text, content column, and the item's own
      # number from a list line. The number is 1 for unordered items, where it
      # is unused. It seeds the counter only when a new level is pushed; within
      # a level the counter increments and the written number is ignored.
      private def parse_list_line(line : String) : {Int32, Bool, String, Int32, Int32}
        indent = line.size - line.lstrip.size
        if match = ORDERED_LIST.match(line)
          number = match[1].to_i? || 1
          content = match[2]
          {indent, true, content, line.size - content.size, number}
        else
          content = line.match!(UNORDERED_LIST)[1]
          {indent, false, content, line.size - content.size, 1}
        end
      end

      # Updates the list nesting stack for a new item at *indent*.
      private def update_list_stack(indent : Int32, ordered : Bool, content_indent : Int32, number : Int32) : Nil
        if @list_stack.empty? || indent > @list_stack.last[:indent]
          push_list_level(indent, ordered, content_indent, number)
        elsif indent < @list_stack.last[:indent]
          while @list_stack.size > 1 && @list_stack.last[:indent] > indent
            @list_stack.pop
          end
          increment_counter(content_indent) if ordered
        elsif ordered != @list_stack.last[:ordered]
          @list_stack.pop
          push_list_level(indent, ordered, content_indent, number)
        else
          increment_counter(content_indent) if ordered
        end
      end

      # Pushes a new level onto the list stack, seeding an ordered level with
      # the number written on its first item.
      private def push_list_level(indent : Int32, ordered : Bool, content_indent : Int32, number : Int32) : Nil
        @list_stack << {indent: indent, ordered: ordered, counter: ordered ? number : 0, content_indent: content_indent}
      end

      # Increments the counter on the top stack entry, preserving all other fields.
      private def increment_counter(content_indent : Int32) : Nil
        last = @list_stack.pop
        @list_stack << {indent: last[:indent], ordered: last[:ordered], counter: last[:counter] + 1, content_indent: content_indent}
      end

      # Returns the prefix string for the current list depth and type.
      private def list_item_prefix(ordered : Bool) : String
        depth = @list_stack.size - 1
        if ordered
          "  " * depth + @list_stack.last[:counter].to_s + ". "
        else
          "  " * depth + BULLETS[depth % BULLETS.size] + " "
        end
      end

      # Emits one list item. The marker comes from depth, not from the
      # stylesheet; line_prefix is honoured ahead of it, at column zero, so it
      # reads as a gutter beside the indented marker rather than part of it.
      private def emit_list_item(content : String, list_prefix : String) : Nil
        open_block(BlockElement::ListItem)
        style = @stylesheet[BlockElement::ListItem]
        ansi = style.to_ansi
        prefix = style.line_prefix || ""
        erase = (style.bg && !ansi.empty?) ? ANSI::ERASE_LINE : ""
        reset = ansi.empty? ? "" : ANSI::RESET
        @io << ansi << prefix << list_prefix << @inline.render(content, style) << erase << reset << (style.line_suffix || "") << '\n'
        @current_line_empty = false
      end
    end
  end
end
