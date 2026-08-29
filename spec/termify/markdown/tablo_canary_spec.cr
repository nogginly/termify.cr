require "../../spec_helper"

# Canary specs for the tablo dependency.
#
# These do not test Termify. They assert the tablo behaviours Termify's table
# rendering is built on, so that bumping the pinned version in shard.yml fails
# here -- loudly and with an explanation -- rather than producing subtly
# mangled tables somewhere downstream.
#
# If one of these fails after a tablo upgrade, read the comment above it before
# changing anything. The fix is usually in TableRenderer, not in the spec.
Spectator.describe "tablo dependency canaries" do
  # Termify passes plain text to tablo and applies its own ANSI inside the
  # stylers. That only works if tablo measures content BEFORE styling it.
  # If this fails, tablo has started counting escape bytes as visible width
  # and every styled column will be laid out too narrow.
  it "measures column width on unstyled content" do
    plain = Tablo::Table.new([["abc"]]) do |t|
      t.add_column("H") { |row| row[0].as(String) }
    end
    plain.pack(autosize: true)

    styled = Tablo::Table.new([["abc"]],
      body_styler: ->(content : String) { "\e[1m#{content}\e[0m" }) do |t|
      t.add_column("H") { |row| row[0].as(String) }
    end
    styled.pack(autosize: true)

    expect(styled.total_table_width).to eq(plain.total_table_width)
  end

  # Termify needs to know which part of a wrapped cell it is styling, so it
  # relies on the styler's richest form: value, coords, content, line_index.
  # If this fails, that Proc form has changed shape and the cursor mapping in
  # TableRenderer cannot locate a wrapped line within its cell.
  it "offers a styler form carrying coords and line index" do
    seen = [] of {Int32, Int32}
    table = Tablo::Table.new([["one two three four five"]],
      body_styler: ->(_value : Tablo::CellType, coords : Tablo::Cell::Data::Coords, content : String, line_index : Int32) {
        seen << {coords.column_index, line_index}
        content
      }) do |t|
      t.add_column("H", width: 5) { |row| row[0].as(String) }
    end
    table.to_s

    expect(seen).not_to be_empty
    expect(seen.map(&.[1])).to contain(0)
    # A cell wrapped over several lines must report increasing line indices.
    expect(seen.map(&.[1]).max).to be > 0
  end

  # Termify's cursor mapping assumes wrapped lines arrive in reading order,
  # starting at line_index 0 for each cell. If this fails, the mapping will
  # attribute styling to the wrong span of text.
  it "emits wrapped lines in order from zero" do
    indices = [] of Int32
    table = Tablo::Table.new([["alpha beta gamma delta"]],
      body_styler: ->(content : String, line_index : Int32) {
        indices << line_index
        content
      }) do |t|
      t.add_column("H", width: 6) { |row| row[0].as(String) }
    end
    table.to_s

    expect(indices).to eq((0...indices.size).to_a)
  end

  # Termify writes to a caller-supplied IO, so it disables tablo's tty-only
  # styling gate. If this property disappears or is renamed, table styling
  # silently vanishes whenever output is piped -- which is exactly the bug
  # this setting was introduced to fix.
  it "allows styling to be enabled independently of a tty" do
    was = Tablo::Config.styler_tty_only?
    begin
      Tablo::Config.styler_tty_only = false
      table = Tablo::Table.new([["x"]],
        body_styler: ->(content : String) { "\e[1m#{content}\e[0m" }) do |t|
        t.add_column("H") { |row| row[0].as(String) }
      end
      expect(table.to_s).to contain("\e[1m")
    ensure
      Tablo::Config.styler_tty_only = was
    end
  end

  # Termify restores Tablo::Config flags after use, which assumes they are
  # writable class properties rather than constants.
  it "exposes writable global config flags" do
    was = Tablo::Config.terminal_capped_width?
    begin
      Tablo::Config.terminal_capped_width = !was
      expect(Tablo::Config.terminal_capped_width?).to eq(!was)
    ensure
      Tablo::Config.terminal_capped_width = was
    end
  end
end
