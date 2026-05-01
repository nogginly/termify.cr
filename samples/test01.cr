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

-   Level 1 Lorem ipsum dolor sit amet
-   Level 1 Lorem ipsum dolor sit amet
    -   Level 2 Lorem ipsum dolor sit amet
        -   Level 3 Lorem ipsum dolor sit amet
        -   Level 3 Lorem ipsum dolor sit amet
        -   Level 3 Lorem ipsum dolor sit amet
-   Level 1 Lorem ipsum dolor sit amet

#### Ordered

1. Lorem ipsum dolor sit amet
2. Lorem ipsum dolor sit amet
  5. Lorem ipsum dolor sit amet
  5. Lorem ipsum dolor sit amet
3. Lorem ipsum dolor sit amet

#### Start numbering with offset:

57. Lorem ipsum dolor sit amet
1. Lorem ipsum dolor sit amet

#### Lists with paragraphs

1. First item

   This is the second paragraph of the first item. Indent to keep it within the list item.

2. Second item



   ```
   This is the second paragraph of the second item.
   ```

3. Third item

    Heading | Heading
    --------|--------
    Value   | Value2

4. Fourth item

#### Checkboxes

- [ ] Lorem ipsum dolor sit amet
- [x] Lorem ipsum dolor sit amet
- [ ] Lorem ipsum dolor sit amet

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

|Heading1|Heading2                      |Heading 3                 |
|--------|------------------------------|--------------------------|
|row1    |                              |Lorem ipsum dolor sit amet|
|row2    |Lorem ipsum _dolor_ sit amet  |                          |
|row3    |Lorem ipsum **dolor** sit amet|                          |

Right aligned columns

|Heading1|                    Heading2|
|-------:|---------------------------:|
|    row1|  Lorem ipsum dolor sit amet|
|    row2|Lorem ipsum `dolor` sit amet|
|    row3|  Lorem ipsum dolor sit amet|

### HTML

This is inline <span style="color: red;">html</span>

<audio controls>
    <source src="/uploads/medium-drill-burst.mp3" type="audio`/mpeg" />
    Your browser does not support the audio element.
</audio>

### XSS Atack

<script>alert('XSS Atack. When you see this you should use sanitizer.')</script>

MD

ss = Termify.markdown_stylesheet({
  :h1          => {bold: true, line_prefix: "# ", newline_after: true, fg: "#aa01ff"},
  :h2          => {bold: true, line_prefix: "## ", newline_after: true},
  :h3          => {bold: true, line_prefix: "### ", newline_after: true},
  :h4          => {bold: true, line_prefix: "=== ", line_suffix: " ===", newline_after: true},
  :h5          => {bold: true, line_prefix: "--- ", line_suffix: " ---", newline_after: true},
  :h6          => {bold: true, underline: true, newline_after: true},
  :code_block  => {fg: "rosy_brown", line_prefix: "~ "},
  :code_inline => {fg: :red},
  :html_tag    => {dim: true},
  :block_html  => {dim: true},
  :block_quote => {line_prefix: "│ "},
})

Termify.render_markdown(STDOUT, ss) do |io|
  MARKDOWN.each_line do |line|
    io.puts(line)
  end
end
