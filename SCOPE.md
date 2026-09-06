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

**Unterminated code fence loses its body.** `reset` closes the quote renderer and
flushes tables, but never closes `@code_renderer`. With a highlight theme the code
renderer buffers until close, so a document ending mid-fence silently drops the
code. Close it in `reset` alongside the others.

**Report gather progress for line-level assembly.** `GatherEvent` covers tables
and highlighted code blocks. It does not cover a single long line arriving in
many chunks, which streams a partial line and reports nothing. Add a kind for it
only if that pause turns out to be perceptible.

**Widen syntax-highlighting coverage.** Only JavaScript has been exercised
meaningfully. Test more languages against the buffering path, and consider
upstreaming a `format_line` or resumable-tokenizer API to tartrazine.
