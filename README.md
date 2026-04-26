# termify

A Crystal shard for rendering Markdown to terminal IO.

> See the end of this document for my AI disclosure.

## Installation

1. Add the dependency to your `shard.yml`:

   ```yaml
   dependencies:
     termify:
       github: nogginly/termify.cr
   ```

2. Run `shards install`

## Usage

```crystal
require "termify"
```

### Rendering Markdown

```cr
Termify.render_markdown do |io|
  io.puts "# Hello"
  io << "_Hello_, **World!**
end
```

## Development

See [DEVELOPMENT](./DEVELOPMENT.md)

## Contributions, by invitation!

*With apologies*, at this time contributions are *by invitation only* and limited to people I know and see often.

These are early days for _Termify_ and I am busy with family and work.

At this time I want to work on this at a manageable pace.

## AI Disclosure

I worked with Claude's Sonnet 4.6 (Adaptive) via the web UI using a free plan to develop this shard. It was an iterative process. I started with a motivation + planning prompt and then worked through the design until it was ready to start implementing.

One difference: for the `xlsx.cr` project I worked with a single session over multiple days. This time I wanted to try working with multiple sessions, handing off after each day.

Here's the opening prompt:

> I would like to implement a Crystal shard / library that will allow me to convert incoming Markdown text and convert and render to a terminal with ANSI escape > code formatting applied based on the type of Markdown. The incoming text will arrive in fragments, which means we don't always have entire lines or blocks, and > which means the renderer needs to maintain current state as fragments arrive.
>
> I am considering two ways to do this:
>
> 1. Gather of fragments and process them a line at a time.
> 2. Process the fragments as they arrive.
>
> In either case I need to keep track of the markdown style, and since markdown can represent nested styles (e.g. indented lists, nested block quotes) and > multi-line styles (e.g. code blocks, block quotes) I think we might need to maintain a stack of nested styles, pushing and popping as blocks start and end.
>
> In the second case, we will need to track line and position (or maybe only if we're starting a line, not sure) so we can detect change in style govered by line ending.
>
> Additionally, since some styles are inline vs block-based (e.g. bold, italic, etc) we may need to keep track of those in a separate stack which could be reset > at block boundaries without impacting the block-style stack.
>
> In terms of API, I want it to be compatible with `IO` in that
>
> * Create renderer  instance with output IO, default to `STDOUT`.
> * Accept fragments via `<<` method
> * Expect line breaks within fragments
>
> Since people have preferences and sometimes accessibility needs, I want to be able to specify a stylesheet for the supported markdown styles as an optional > configuration when instantiating the renderer, with a reasonable default in place.
>
> Before we implement anything, let me know what you think.
>

> DRAFT analysis below ... more soon.

We didn't start implementing a single file until we were clear about the following:

- Usage pattern for the API, both to make fresh XLSX document and to be able to use a template.
- File / folder structure, keeping internals isolated, and well separated from the main components
- Testing (using `spectator`) from the beginning, which Claude had to learn about

It took several days and many stops and starts because I'm using the free plan and ran out of my "free messages" often. The lesson learned from the `xlsx.cr` project was that the breaks gave me time to think and understand the work done, and this in turn helped me formulate next steps better.

At the end of the first day, and every day, I asked Claude to create a handoff document that I then pasted in with a continuation prompt in a fresh session.

Interestingly, this made the experience more tedious. The handoff over the days lost information, especially some design decisions from day 1 and 2 disappeared and I had to notice and remind Claude. It also, I think, took more time since Claude had to "re-learn" code across handoff sessions.

> I need to think about this some more
