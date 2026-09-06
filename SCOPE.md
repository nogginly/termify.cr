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

Nothing outstanding.

---

## Will fix

**Make `SubScroller` testable.** It writes with bare `print` to `STDOUT`, which is
why its specs are blocked on a live TTY. Inject `io : IO = STDOUT` at
`initialize`; `start`/`stop` then assert against an `IO::Memory` with only
`cursor_row` stubbed. While in there: replace the hand-rolled escapes with the
`ANSI::Cursor` and `ANSI::Clear` helpers next door, and remove
`self.write_thinking_chunk`, which belongs to some other application.

**Recover five missing stylesheet specs.** The suite went from 246 examples to 241
across the spec split; a `str_replace` likely clobbered content in
`stylesheet_spec.cr`. Compare against repo history.

**Widen syntax-highlighting coverage.** Only JavaScript has been exercised
meaningfully. Test more languages against the buffering path, and consider
upstreaming a `format_line` or resumable-tokenizer API to tartrazine.
