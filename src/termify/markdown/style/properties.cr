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

    # Per-line decoration for block elements only.
    module BlockLayoutProperties
      getter line_prefix : String?
      getter line_suffix : String?
    end
  end
end
