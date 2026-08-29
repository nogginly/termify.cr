# Termify Scope

Known and pending work. Items are deleted when done, never marked done. The goal
is an empty file.

Two buckets, split on one question: **is it wrong, or just untidy?**

- **Must fix** -- correctness. Shipping it is a bug.
- **Will fix** -- agreed work that is not a defect. Tidying, refactors, docs, tests.

Anything that is neither belongs in [DESIGN.md Appendix A](./DESIGN.md#appendix-a--deliberately-unsupported)
as deliberately unsupported, or nowhere at all.

---

## Must fix

**Table detection matches ordinary prose.** `TABLE_ROW` is
`/^(\|.*\|)|(.*(\|.*)+)$/`; alternation binds looser than the anchors, so the
second branch has no start anchor and the first has no end anchor. Any line
containing a pipe enters `BlockMode::Table` -- including `if x || y` and, because
`process_table_line` runs before `dispatch_block`, headings such as `# Title | Sub`.
Anchor both branches, and consider letting heading and fence detection win over
table detection.

**Table output depends on whether STDOUT is a TTY.** `TableRenderer` styles
borders and the header row through `Colorize`, whose `enabled` flag defaults to
`STDOUT.tty? && STDERR.tty?`. Everything else in the shard emits ANSI
unconditionally via the `ANSI` module. Rendering the same Markdown into an
`IO::Memory` therefore yields different bytes interactively than in a pipe, which
is wrong for a library that hands output to a caller-supplied IO -- the caller
decides where it goes, and may know better than `STDOUT` does. It also makes specs
pass locally and fail in CI. Route table styling through `ANSI` and let the
stylesheet own the decision.

**Inline styling is discarded in table cells.** `buffer_table_row` runs
`render_inline` over every cell, then `TableRenderer` strips all escape sequences
back out via `strip_escaped_codes` before handing text to tablo, which counts
escape bytes as visible width. Bold, colour and links are therefore lost in tables,
and the work of rendering them is wasted. The behaviour is also inconsistent: the
`render_raw_table` fallback keeps the escapes, so styling appears only when tablo
fails. A fix needs tablo to size columns on a display width supplied by the caller,
or the styling to be re-applied to cell text after layout.

**A blockquote after a table swallows the table.** In `process_line`,
`process_quote_line` runs before `process_table_line`. When a confirmed table is
open and the next line starts with `>`, the quote handler consumes it and
`flush_table` never runs, so the buffered rows are dropped. Same root cause as the
stranded-candidate problem -- a later handler consuming a line that an earlier
state machine still needed. Either flush the table before quote routing, or hoist
the open-table check the way `resolve_table_candidate` was hoisted.

**Table detection is confused by escaped and inline-code pipes.** `table_row?`
counts any pipe, so `` `a | b` `` in prose and `a \| b` both raise a candidate.
Harmless today -- the candidate is released as a paragraph unless a delimiter row
happens to follow -- but the same blindness would produce wrong cell splits in
`buffer_table_row` for a real table containing either.

**`Terminal#cursor_row` can hang forever.** The read loop breaks on `'R'`, but
`STDIN.read_char` returns `nil` at EOF, which never equals `'R'`. Any non-TTY stdin
-- CI, a pipe, a redirect -- spins the loop indefinitely. Break on `nil`, and
bound the read.

**Unsupported-platform guard is runtime code.** `terminal.cr` ends with a bare
`raise` inside a `{% else %}` branch, so an unsupported target compiles and fails
at program start instead of at build time. Use `{% raise %}`.

**`emit_styled` mutates renderer state when writing to a foreign IO.**
`buffer_table_row` passes a `String::Builder`. The `open_block` call is guarded by
`io.same?(@io)` but the trailing `@current_line_empty = text.empty?` is not, so
rendering a table cell rewrites the parent's blank-line accounting. Extend the
guard to cover both.

**`TableRenderer` leaks global state on failure.** `Tablo::Config.terminal_capped_width`
is set true, used, then set false with no `ensure`; if `pack` raises, the flag stays
on for the life of the process. The surrounding `rescue ex` also swallows the
exception silently with `ex` unused.

**Pending blank line bypasses block accounting.** `handle_list_line` writes
`@io << '\n'` directly on list exit without updating `@current_line_empty`, so the
following `open_block` can emit a second blank line.

---

## Will fix

**Make `SubScroller` testable.** It writes with bare `print` to `STDOUT`, which is
why its specs are blocked on a live TTY. Inject `io : IO = STDOUT` at
`initialize`; `start`/`stop` then assert against an `IO::Memory` with only
`cursor_row` stubbed. While in there: replace the hand-rolled escapes with the
`ANSI::Cursor` and `ANSI::Clear` helpers next door, and remove
`self.write_thinking_chunk`, which belongs to some other application.

**Extract `Markdown::InlineRenderer`.** `Renderer` is 754 lines and about forty
private methods. `render_inline` plus its eight scanners and helpers is ~250 lines
with a single dependency, the stylesheet. Extracting it roughly halves the class
and lets `inline_spec.cr` test the scanner directly.

**Replace cross-instance private access.** `close_quote_renderer` reads
`r.@current_line_empty`. Legal, but brittle; expose a `protected getter`.

**Fix `Stylesheet` aliasing and silent downgrade.** The primary constructor stores
the caller's hashes by reference while the `merge:` path `dup`s -- make both dup.
Separately, `code_block_style` falls back to `CodeBlockStyle::NONE` when someone
assigns a plain `BlockStyle` via `[]=`, silently discarding their fg/bg; promote
via `CodeBlockStyle.new.merge(s)` instead.

**Remove or adopt dead ANSI helpers.** `ANSI.sequence` and `ANSI.reset_and_replay`
have no callers; `Renderer#replay_sequence` does the job. Delete them, or route the
renderer through them.

**Move the `TableRenderer` regex to a named constant.** `strip_escaped_codes` holds
an inline regex, against the project rule that all regexes live in private named
constants. The 80 and 100 column thresholds nearby should be named too.

**Recover five missing stylesheet specs.** The suite went from 246 examples to 241
across the spec split; a `str_replace` likely clobbered content in
`stylesheet_spec.cr`. Compare against repo history.

**Fix stale comments.** `process_fence_line` carries a duplicated doc comment; the
"Renders buffered rows via TableRenderer" comment sits above `list_visual_indent`
rather than `flush_table`; `process_list_item` and `update_list_stack` share an
identical comment.

**Fix README usage snippet.** The rendering example has an unterminated string
literal and a missing `end`, and the samples section says `mdterm.cr` where it
means `md2term.cr`.

**Widen syntax-highlighting coverage.** Only JavaScript has been exercised
meaningfully. Test more languages against the buffering path, and consider
upstreaming a `format_line` or resumable-tokenizer API to tartrazine.
