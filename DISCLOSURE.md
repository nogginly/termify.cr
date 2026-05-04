# AI Usage Disclosure for Termify

This shard is part of my experimentation with using an LLM to build small, well-defined libraries _that I understand as if I wrote it myself_ for use by my otherwise hand-written applications.

The "[Using AI to Contribute to Open Source](https://www.visidata.org/blog/2026/ai/)" article provides an excellent framework for identifying how AI is used.

Based on that, `termify.cr` is _by design_ a **[Level 5](https://www.visidata.org/blog/2026/ai/#level-5%3A-bots-coded%2C-human-understands-completely)** project.

> Updated 2026-05-04

## Approach

I worked with Claude's Sonnet 4.6 (Adaptive) via the web UI using a free plan to develop this shard. It was an iterative process. I started with a motivation + planning prompt and then worked through the design until it was ready to start implementing.

One difference: with the [`xlsx.cr`](https://github.com/nogginly/xlsx.cr) project I worked with a single Claude session over multiple days. This time I wanted to try working with multiple sessions, handing off after roughly each day.

## Opening prompt

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

## Engagement

We didn't start implementing a single file until we were clear about the following:

- Usage pattern for the API, both to make fresh XLSX document and to be able to use a template.
- File / folder structure, keeping internals isolated, and well separated from the main components
- Testing (using `spectator`) from the beginning, which Claude had to learn about

It took several days and many stops and starts because I'm using the free plan and ran out of my "free messages" often. The lesson learned from the `xlsx.cr` project was that the breaks gave me time to think and understand the work done, and this in turn helped me formulate next steps better.

At the end of the first day, and every day or so afterward, I asked Claude to create a handoff document that I then pasted in with a continuation prompt in a fresh session.

## To split a session, or not

Interestingly, this made the experience more tedious. The handoff over the days lost information, especially some design decisions from day 1 and 2 disappeared.

Given my desire to understand the code entirely, I was able to notice these and remind Claude.

It also, I think, took more time since Claude had to "re-learn" code across handoff sessions.

After five such hand-offs, I almost decided to continue with one session. But I decided to persevere, albeit at a slower pace, handing off from a session to a new one at a major feature boundary.

## How much to hand-off

After the first few hand-offs I noticed that I didn't gain the token benefit I was hoping for. This was mainly due to the hand-off document including all the source code, and over time the project was getting bigger and the hand-off was itself now expensive.

While I was maintaining a Github repo through the project, it was private. At this point I decided to make the project public and after some discussion worked out a hand-off approach that no longer included the code.

In hindsight this is obvious. Letting Claude access the public repo (readonly!) and carrying only our design considerations and decisions and lessons learned across sessions made the sessions much more efficient _once_ the project reached a certain size.

## Lessons

For my next Level 5 project I plan to (a) use a single session to get to a minimal functional state, and (b) switch to multi-session by making the repo public and using a lean hand-off.
