# frozen_string_literal: true

require_relative "spec_helper"
require_relative "support/tty_input"
require "stringio"
require "forge_cli/guard"

describe ForgeCli::Guard do
  CONFIRM = { action: "overwrite the .env of example.com", token: "example.com" }.freeze

  def confirm!(stdin, yes: false)
    out = StringIO.new
    ForgeCli::Guard.confirm!(CONFIRM, yes: yes, stdin: stdin, command: "env-set", out: out)
    out.string
  end

  it "skips the prompt entirely with --yes" do
    stdin = StringIO.new("")
    assert_equal "", confirm!(stdin, yes: true)
    assert_equal 0, stdin.pos
  end

  it "refuses a non-TTY stdin without --yes, pointing at --yes and -d" do
    error = assert_raises(ForgeCli::GuardRefused) { confirm!(StringIO.new("example.com\n")) }
    assert_includes error.message, "env-set"
    assert_includes error.message, "--yes"
    assert_includes error.message, "-d"
  end

  it "passes when the typed name matches, ignoring surrounding whitespace" do
    out = confirm!(TtyInput.new("  example.com  \n"))
    assert_includes out, "This will overwrite the .env of example.com. This cannot be undone."
    assert_includes out, "Type example.com to confirm: "
  end

  it "aborts on a mismatch, including a case difference" do
    error = assert_raises(ForgeCli::Aborted) { confirm!(TtyInput.new("Example.com\n")) }
    assert_includes error.message, "nothing was changed"
  end

  it "aborts on end of input" do
    assert_raises(ForgeCli::Aborted) { confirm!(TtyInput.new("")) }
  end

  it "compares against an integer token as text" do
    out = StringIO.new
    ForgeCli::Guard.confirm!({ action: "delete daemon 7", token: 7 }, yes: false, stdin: TtyInput.new("7\n"),
                                                                      command: "daemon-delete", out: out)
    assert_includes out.string, "Type 7 to confirm"
  end
end
