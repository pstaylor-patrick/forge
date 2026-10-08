# frozen_string_literal: true

require_relative "spec_helper"
require "forge_cli/env_file"

describe ForgeCli::EnvFile do
  M = ForgeCli::EnvFile::MASK

  def mask(content) = ForgeCli::EnvFile.mask(content)
  def entries(content) = ForgeCli::EnvFile.entries(content)

  describe ".mask" do
    it "masks every non-empty value with a fixed width" do
      assert_equal "APP_KEY=#{M}\nX=#{M}\n", mask("APP_KEY=base64:abcdef==\nX=1\n")
    end

    it "never reveals a value's length" do
      assert_equal mask("A=1\n"), mask("A=#{'x' * 200}\n")
    end

    it "keeps an empty value empty, quoted or not" do
      assert_equal "A=\nB=\nC=\n", mask("A=\nB=\"\"\nC=''\n")
    end

    it "masks quoted values" do
      assert_equal "A=#{M}\nB=#{M}\n", mask("A=\"hello world\"\nB='single'\n")
    end

    it "collapses a multi-line quoted value to one masked line" do
      content = "KEY=\"-----BEGIN KEY-----\nline2\nline3-----END KEY-----\"\nNEXT=1\n"
      assert_equal "KEY=#{M}\nNEXT=#{M}\n", mask(content)
    end

    it "does not end a double-quoted value at an escaped quote" do
      content = "A=\"one \\\" still open\nclosed\"\nB=2\n"
      assert_equal "A=#{M}\nB=#{M}\n", mask(content)
    end

    it "keeps the export prefix" do
      assert_equal "export A=#{M}\n", mask("export A=secret\n")
    end

    it "keeps comments and blank lines, normalizing whitespace-only lines" do
      assert_equal "# app settings\n\nA=#{M}\n", mask("# app settings\n   \nA=1\n")
    end

    it "masks a commented-out assignment's value" do
      assert_equal "# OLD_SECRET=#{M}\n# EMPTY=\n", mask("#OLD_SECRET=hunter2\n# EMPTY=\n")
    end

    it "hides lines it cannot parse" do
      assert_equal "# (unparsed line hidden)\nA=#{M}\n", mask("this is not an assignment secret\nA=1\n")
    end

    it "treats an unquoted inline comment as no value" do
      assert_equal "A=\n", mask("A= # nothing here\n")
    end

    it "masks the rest of the file when a quote never closes" do
      assert_equal "A=#{M}\n", mask("A=\"never closed\nB=2\n")
    end

    it "handles a file without a trailing newline and an empty file" do
      assert_equal "A=#{M}\n", mask("A=1")
      assert_equal "", mask("")
    end

    it "never contains any value from the input" do
      content = "DB_PASSWORD=p4ss\nKEY=\"multi\nline-secret\"\n#OLD=retired-secret\nexport T='tok'\n"
      masked = mask(content)
      %w[p4ss multi line-secret retired-secret tok].each { |secret| refute_includes masked, secret }
    end
  end

  describe ".entries" do
    it "parses values as the application sees them" do
      items = entries("A=plain\nB=\"quoted \\\"x\\\" \\\\ y\"\nC='single $x'\nD=value # comment\nE=a#b\n")
      values = items.to_h { |e| [e[:key], e[:value]] }
      assert_equal({ "A" => "plain", "B" => "quoted \"x\" \\ y", "C" => "single $x", "D" => "value", "E" => "a#b" },
                   values)
    end

    it "keeps every line so joining raw_lines rebuilds the input" do
      content = "# c\n\nexport A=1\nB=\"x\ny\"\njunk\nC=3"
      assert_equal content, entries(content).flat_map { |e| e[:raw_lines] }.join
    end

    it "types each item and records the export prefix" do
      items = entries("# c\n\nexport A=1\njunk\n")
      assert_equal %i[comment blank entry unparsed], items.map { |e| e[:type] }
      assert items[2][:export]
    end

    it "spans a multi-line value in one entry" do
      item = entries("K=\"a\nb\nc\"\n").first
      assert_equal "a\nb\nc", item[:value]
      assert_equal 3, item[:raw_lines].size
    end
  end

  describe ".set" do
    def set(content, key, value) = ForgeCli::EnvFile.set(content, key, value)

    it "replaces the first entry in place" do
      assert_equal "A=1\nB=new\nC=3\nB=dup\n", set("A=1\nB=2\nC=3\nB=dup\n", "B", "new")
    end

    it "replaces every line of a multi-line entry" do
      assert_equal "K=short\nNEXT=1\n", set("K=\"line1\nline2\"\nNEXT=1\n", "K", "short")
    end

    it "keeps the export prefix" do
      assert_equal "export A=2\n", set("export A=1\n", "A", "2")
    end

    it "appends a missing key, adding a newline first when needed" do
      assert_equal "A=1\nB=2\n", set("A=1\n", "B", "2")
      assert_equal "A=1\nB=2\n", set("A=1", "B", "2")
      assert_equal "B=2\n", set("", "B", "2")
    end

    it "keeps a missing trailing newline when replacing the last line" do
      assert_equal "A=1\nB=new", set("A=1\nB=old", "B", "new")
    end

    it "quotes values that need it and leaves plain ones bare" do
      assert_equal "A=base64:abc/def\n", set("", "A", "base64:abc/def")
      assert_equal %(A="two words"\n), set("", "A", "two words")
      assert_equal %(A="x=1"\n), set("", "A", "x=1")
      assert_equal %(A="$HOME"\n), set("", "A", "$HOME")
      assert_equal %(A="say \\"hi\\" \\\\ ok"\n), set("", "A", %(say "hi" \\ ok))
    end

    it "round-trips any value through entries" do
      ["plain", "two words", %(quote " and \\ slash), "hash # inside", "it's", "multi\nline", ""].each do |value|
        assert_equal value, entries(set("A=1\n", "A", value)).first[:value]
      end
    end

    it "rejects an invalid key" do
      assert_raises(ArgumentError) { set("", "1BAD", "x") }
      assert_raises(ArgumentError) { set("", "A B", "x") }
    end
  end

  describe ".unset" do
    def unset(content, key) = ForgeCli::EnvFile.unset(content, key)

    it "removes every entry for the key, including multi-line ones" do
      assert_equal "A=1\nC=3\n", unset("A=1\nB=\"x\ny\"\nC=3\nB=again\n", "B")
    end

    it "leaves comments and other keys alone, and ignores an unknown key" do
      content = "# B=commented\nA=1\n"
      assert_equal content, unset(content, "B")
    end
  end

  describe ".key_diff" do
    def diff(old, new) = ForgeCli::EnvFile.key_diff(old, new)

    it "reports added, removed, and changed key names, sorted" do
      result = diff("A=1\nB=2\nC=3\n", "C=changed\nA=1\nZ=new\nD=new\n")
      assert_equal({ added: %w[D Z], removed: %w[B], changed: %w[C] }, result)
    end

    it "is empty when only comments or quoting change" do
      assert_equal({ added: [], removed: [], changed: [] }, diff("A=1\n", "# hi\n\nA=\"1\"\n"))
    end

    it "counts a changed duplicate as a change" do
      assert_equal %w[A], diff("A=1\nA=2\n", "A=1\nA=3\n")[:changed]
    end

    it "never contains a value" do
      result = diff("SECRET=old-value\n", "SECRET=new-value\n")
      refute_includes result.inspect, "value"
    end
  end
end
