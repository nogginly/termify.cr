module Termify
  module Markdown
    # SGR attribute flags. Included by all style types.
    module SGRProperties
      getter? bold : Bool
      getter? italic : Bool
      getter? dim : Bool
      getter? underline : Bool
      getter? strikethrough : Bool
    end

    # fg/bg color attributes. Included by all style types.
    module ColorProperties
      getter fg : Colorize::Color?
      getter bg : Colorize::Color?
    end

    # Per-line and per-block decoration for block elements only.
    # line_prefix/line_suffix -- prepended/appended on every rendered line.
    # newline_before/newline_after -- emit one blank line before/after the
    #   semantic block. The renderer collapses adjacent flags with OR so
    #   neighbouring blocks never produce more than one blank line between them.
    module BlockLayoutProperties
      getter line_prefix : String?
      getter line_suffix : String?
      getter? newline_before : Bool
      getter? newline_after : Bool
    end
  end
end
