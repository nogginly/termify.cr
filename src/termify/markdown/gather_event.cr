module Termify
  module Markdown
    # What the renderer is holding back. Both kinds must be seen whole before
    # any of them can be rendered: a table needs every row to size its columns,
    # a highlighted code block needs the whole body to tokenize.
    enum GatherKind
      Table
      CodeBlock
    end

    # Where a gather has got to. Started is followed by zero or more Progressed
    # and then exactly one Finished, always for the same kind.
    enum GatherPhase
      Started
      Progressed
      Finished
    end

    # Reported while the renderer accumulates content it cannot yet render.
    # units counts rows for a table and lines for a code block, and is the
    # total so far rather than an increment.
    record GatherEvent,
      phase : GatherPhase,
      kind : GatherKind,
      units : Int32
  end
end
