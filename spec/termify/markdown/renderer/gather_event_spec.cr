require "../../../spec_helper"

Spectator.describe Termify::Markdown::Renderer do
  include Termify
  include Termify::Markdown

  # Collects every event so a spec can assert on the sequence rather than on
  # any single call.
  class Recorder
    getter events = [] of GatherEvent

    def handler : Proc(GatherEvent, Nil)
      ->(event : GatherEvent) { @events << event; nil }
    end

    def phases : Array(GatherPhase)
      @events.map(&.phase)
    end

    def kinds : Array(GatherKind)
      @events.map(&.kind).uniq
    end
  end

  def render_watching(text : String, sheet : Stylesheet = Stylesheet.default) : Recorder
    rec = Recorder.new
    io = IO::Memory.new
    r = Renderer.new(io, sheet, rec.handler)
    r.feed(text)
    r.close
    rec
  end

  TABLE = "| a | b |\n| --- | --- |\n| 1 | 2 |\n| 3 | 4 |\n"

  # The handler writes into the same IO as the renderer, so the transcript
  # shows the true interleaving. A caller must be able to take its spinner
  # down before the table lands on top of it.
  def transcript_for(phase : GatherPhase, text : String, sheet = Stylesheet.default) : String
    io = IO::Memory.new
    marker = ->(event : GatherEvent) {
      io << "<MARK>" if event.phase == phase
      nil
    }
    r = Renderer.new(io, sheet, marker)
    r.feed(text)
    r.close
    io.to_s
  end

  # A cell value that cannot occur inside an ANSI escape sequence.
  UNIQUE_TABLE = "| head | head |\n| --- | --- |\n| ZZTOP | QQBOT |\n"

  # Returns whatever the renderer wrote between Started and Finished. The
  # caller's spinner is on screen for exactly that span, so it must be empty.
  def written_while_gathering(text : String, sheet = Stylesheet.default) : String
    io = IO::Memory.new
    marker = ->(event : GatherEvent) {
      io << "<S>" if event.phase.started?
      io << "<F>" if event.phase.finished?
      nil
    }
    r = Renderer.new(io, sheet, marker)
    r.feed(text)
    r.close
    rendered = io.to_s
    from = rendered.index("<S>")
    to = rendered.index("<F>")
    return "NO PAIR" if from.nil? || to.nil?
    rendered[(from + 3)...to]
  end

  describe "gather events" do
    it "reports nothing when no handler is given" do
      io = IO::Memory.new
      r = Renderer.new(io)
      r.feed(TABLE)
      r.close
      expect(io.to_s).to contain("1")
    end

    it "reports nothing for prose" do
      rec = render_watching("Just a paragraph.\n\nAnd another.\n")
      expect(rec.events).to be_empty
    end

    it "brackets a table with one Started and one Finished" do
      rec = render_watching(TABLE)
      expect(rec.phases.count(GatherPhase::Started)).to eq(1)
      expect(rec.phases.count(GatherPhase::Finished)).to eq(1)
      expect(rec.phases.first).to eq(GatherPhase::Started)
      expect(rec.phases.last).to eq(GatherPhase::Finished)
    end

    it "identifies the kind being gathered" do
      rec = render_watching(TABLE)
      expect(rec.kinds).to eq([GatherKind::Table])
    end

    it "counts every buffered row" do
      rec = render_watching(TABLE)
      progressed = rec.events.select { |e| e.phase == GatherPhase::Progressed }
      expect(progressed.size).to eq(4)
      expect(progressed.map(&.units)).to eq([1, 2, 3, 4])
    end

    it "carries the final count on the Finished event" do
      rec = render_watching(TABLE)
      finished = rec.events.last
      expect(finished.phase).to eq(GatherPhase::Finished)
      expect(finished.units).to eq(4)
    end

    it "brackets each of two tables separately" do
      rec = render_watching("#{TABLE}\nBetween.\n\n#{TABLE}")
      expect(rec.phases.count(GatherPhase::Started)).to eq(2)
      expect(rec.phases.count(GatherPhase::Finished)).to eq(2)
    end

    it "reports a table inside a blockquote" do
      quoted = TABLE.lines.map { |line| "> #{line}" }.join('\n')
      rec = render_watching("#{quoted}\n")
      expect(rec.kinds).to eq([GatherKind::Table])
      expect(rec.phases.count(GatherPhase::Started)).to eq(1)
      expect(rec.phases.count(GatherPhase::Finished)).to eq(1)
    end

    it "finishes a table left open when the renderer closes" do
      rec = Recorder.new
      io = IO::Memory.new
      r = Renderer.new(io, Stylesheet.default, rec.handler)
      r.feed("| a | b |\n| --- | --- |\n| 1 | 2 |\n")
      expect(rec.phases).to_not contain(GatherPhase::Finished)
      r.close
      expect(rec.phases.last).to eq(GatherPhase::Finished)
    end

    it "keeps rendering when the handler raises" do
      io = IO::Memory.new
      exploding = ->(_event : GatherEvent) { raise "handler is broken"; nil }
      r = Renderer.new(io, Stylesheet.default, exploding)
      r.feed(TABLE)
      r.close
      expect(io.to_s).to contain("1")
    end

    it "reports Finished before any of the table is written" do
      rendered = transcript_for(GatherPhase::Finished, UNIQUE_TABLE)
      mark = rendered.index("<MARK>") || Int32::MAX
      content = rendered.index("ZZTOP") || Int32::MIN
      expect(mark).to be < content
    end

    it "reports Started before any of the table is written" do
      rendered = transcript_for(GatherPhase::Started, UNIQUE_TABLE)
      mark = rendered.index("<MARK>") || Int32::MAX
      content = rendered.index("ZZTOP") || Int32::MIN
      expect(mark).to be < content
    end

    it "writes nothing at all while gathering a table" do
      expect(written_while_gathering(UNIQUE_TABLE)).to eq("")
    end

    it "writes nothing while gathering a table that follows a paragraph" do
      expect(written_while_gathering("Some prose.\n\n#{UNIQUE_TABLE}")).to eq("")
    end
  end

  describe "gather events for code blocks" do
    def highlighted : Stylesheet
      Stylesheet.new({:code_block => {highlight_theme: "catppuccin-macchiato"}},
        merge: Stylesheet.default)
    end

    it "brackets a highlighted fence" do
      rec = render_watching("```crystal\nputs 1\nputs 2\n```\n", highlighted)
      expect(rec.kinds).to eq([GatherKind::CodeBlock])
      expect(rec.phases.count(GatherPhase::Started)).to eq(1)
      expect(rec.phases.count(GatherPhase::Finished)).to eq(1)
    end

    it "counts the body lines of a highlighted fence" do
      rec = render_watching("```crystal\nputs 1\nputs 2\n```\n", highlighted)
      expect(rec.events.last.units).to eq(2)
    end

    it "reports nothing for a fence with no highlight theme" do
      rec = render_watching("```crystal\nputs 1\n```\n")
      expect(rec.events).to be_empty
    end

    # A theme is not enough: tartrazine has no lexer for every fenced language,
    # and CodeRenderer streams plain text when it cannot find one. Reporting a
    # gather there would raise a caller's spinner over output already flowing.
    it "reports nothing for a language tartrazine cannot highlight" do
      rec = render_watching("```notalanguage\nsome text\nmore text\n```\n", highlighted)
      expect(rec.events).to be_empty
    end

    it "reports nothing for a fence with no language" do
      rec = render_watching("```\nsome text\n```\n", highlighted)
      expect(rec.events).to be_empty
    end

    it "still writes the body of an unhighlightable fence" do
      io = IO::Memory.new
      r = Renderer.new(io, highlighted)
      r.feed("```notalanguage\nZZTOP\n```\n")
      r.close
      expect(io.to_s).to contain("ZZTOP")
    end

    it "finishes a highlighted fence left unclosed" do
      rec = Recorder.new
      io = IO::Memory.new
      r = Renderer.new(io, highlighted, rec.handler)
      r.feed("```crystal\nputs 1\n")
      r.close
      expect(rec.phases.last).to eq(GatherPhase::Finished)
    end

    it "reports Finished before the highlighted body is written" do
      rendered = transcript_for(GatherPhase::Finished,
        "```crystal\nZZTOP = 1\n```\n", highlighted)
      mark = rendered.index("<MARK>") || Int32::MAX
      content = rendered.index("ZZTOP") || Int32::MIN
      expect(mark).to be < content
    end

    it "writes nothing at all while gathering a highlighted fence" do
      expect(written_while_gathering("```crystal\nZZTOP = 1\n```\n", highlighted))
        .to eq("")
    end

    # The reported case: a fence opening straight after a list item, where the
    # block's top margin was emitted on the first body line.
    it "writes nothing while gathering a fence that follows a list item" do
      md = "1. Add the dependency:\n```crystal\nZZTOP = 1\n```\n"
      expect(written_while_gathering(md, highlighted)).to eq("")
    end

    it "writes nothing while gathering a fence that follows a paragraph" do
      md = "Some prose.\n\n```crystal\nZZTOP = 1\n```\n"
      expect(written_while_gathering(md, highlighted)).to eq("")
    end
  end
end
