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
