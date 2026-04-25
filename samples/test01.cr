require "../src/termify"

MARKDOWN = <<-MD
### Headings

# h1 Heading

## h2 Heading

### h3 Heading

#### h4 Heading

##### h5 Heading

###### h6 Heading

### Links

[Link text](/)

[Link with title](/blog 'My blog!')

### Images

![Markdown logo](/uploads/Markdown-Logo.webp)
![Syki Logo](/logo512.png 'My logo')

### Lists

#### Unordered

-   Lorem ipsum dolor sit amet
-   Lorem ipsum dolor sit amet
    -   Lorem ipsum dolor sit amet
        -   Lorem ipsum dolor sit amet
        -   Lorem ipsum dolor sit amet
        -   Lorem ipsum dolor sit amet
-   Lorem ipsum dolor sit amet

#### Ordered

1. Lorem ipsum dolor sit amet
2. Lorem ipsum dolor sit amet
3. Lorem ipsum dolor sit amet

Start numbering with offset:

57. Lorem ipsum dolor sit amet
1. Lorem ipsum dolor sit amet

#### Checkboxes

-   [ ] Lorem ipsum dolor sit amet
-   [x] Lorem ipsum dolor sit amet
-   [ ] Lorem ipsum dolor sit amet

### Emphasis

**Bold text**

_Italic text_

~~Strikethrough~~

### Horizontal Rule

---

### Blockquotes

> Blockquotes
>
> > Nested blockquotes
> >
> > > Nested blockquotes

### Code

Inline `code`

```
Sample text here...
```

Syntax highlighting

```js
var foo = function (bar) {
    return bar++
}

console.log(foo(5))
```

### Tables

| Heading1 | Heading2                   | Heading 3
| -------- | -------------------------- |-------------
| row1     | | Lorem ipsum dolor sit amet |
| row2     | Lorem ipsum _dolor_ sit amet |
| row3     | Lorem ipsum **dolor** sit amet |

Right aligned columns

| Heading1 |                   Heading2 |
| -------: | -------------------------: |
|     row1 | Lorem ipsum dolor sit amet |
|     row2 | Lorem ipsum `dolor` sit amet |
|     row3 | Lorem ipsum dolor sit amet |

### HTML

This is inline <span style="color: red;">html</span>

<audio controls>
    <source src="/uploads/medium-drill-burst.mp3" type="audio`/mpeg" />
    Your browser does not support the audio element.
</audio>

### XSS Atack

<script>alert('XSS Atack. When you see this you should use sanitizer.')</script>

MD

ss = Termify::Markdown::Stylesheet.new({
  # ── headings — bold + colour hierarchy, no literal prefix ───────
  Termify::Markdown::Element::H1 => Termify::Markdown::Style.new(bold: true, underline: true, fg: Termify::ANSI::FG_BRIGHT_WHITE),
  Termify::Markdown::Element::H2 => Termify::Markdown::Style.new(bold: true, fg: Termify::ANSI::FG_BRIGHT_WHITE),
  Termify::Markdown::Element::H3 => Termify::Markdown::Style.new(bold: true, fg: Termify::ANSI::FG_WHITE),
  Termify::Markdown::Element::H4 => Termify::Markdown::Style.new(bold: true, dim: true),
  Termify::Markdown::Element::H5 => Termify::Markdown::Style.new(italic: true, dim: true),
  Termify::Markdown::Element::H6 => Termify::Markdown::Style.new(dim: true),

  # ── block elements ───────────────────────────────────────────────
  Termify::Markdown::Element::Paragraph      => Termify::Markdown::Style::NONE,
  Termify::Markdown::Element::Blockquote     => Termify::Markdown::Style.new(prefix: "| "),
  Termify::Markdown::Element::CodeBlock      => Termify::Markdown::Style.new(fg: Termify::ANSI::FG_BRIGHT_WHITE, bg: Termify::ANSI::BG_BRIGHT_BLACK),
  Termify::Markdown::Element::HorizontalRule => Termify::Markdown::Style.new(dim: true),
  Termify::Markdown::Element::ListItem       => Termify::Markdown::Style.new(prefix: "* "),
  Termify::Markdown::Element::Table          => Termify::Markdown::Style.new(dim: false),

  # ── inline elements ──────────────────────────────────────────────
  Termify::Markdown::Element::CodeInline    => Termify::Markdown::Style.new(fg: Termify::ANSI::FG_CYAN),
  Termify::Markdown::Element::Bold          => Termify::Markdown::Style.new(bold: true),
  Termify::Markdown::Element::Italic        => Termify::Markdown::Style.new(italic: true),
  Termify::Markdown::Element::Strikethrough => Termify::Markdown::Style.new(strikethrough: true),
  Termify::Markdown::Element::Link          => Termify::Markdown::Style.new(underline: true, fg: Termify::ANSI::FG_BRIGHT_BLUE),
  Termify::Markdown::Element::HtmlTag       => Termify::Markdown::Style.new(fg: Termify::ANSI::FG_RED),
  Termify::Markdown::Element::BlockHtml     => Termify::Markdown::Style.new(italic: true, fg: Termify::ANSI::FG_RED),
})

mdr = Termify::Markdown::Renderer.new(STDOUT, ss)
MARKDOWN.each_line do |line|
  mdr.puts(line)
end
