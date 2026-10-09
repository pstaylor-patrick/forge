# frozen_string_literal: true

require_relative "spec_helper"
require "fileutils"
require "json"
require "stringio"
require "tmpdir"
require_relative "../install"

describe Install::Installer do
  def repo = File.realpath(File.expand_path("..", __dir__))

  before do
    @home = Dir.mktmpdir("forge-install-home")
    @out = StringIO.new
  end

  after { FileUtils.rm_rf(@home) }

  def install!
    Install::Installer.new(repo: repo, home: @home, out: @out).run
  end

  def path(*parts) = File.join(@home, *parts)
  def bin_link = path(".local", "bin", "forge")

  it "links the binary and the skill into every agent" do
    install!

    assert File.symlink?(bin_link)
    assert_equal File.join(repo, "bin", "forge"), File.readlink(bin_link)

    claude = path(".claude", "skills", "forge")
    assert File.symlink?(claude)
    assert_equal File.join(repo, "skills", "forge"), File.readlink(claude)

    pi = JSON.parse(File.read(path(".pi", "agent", "settings.json")))
    assert_equal [path(".claude", "skills")], pi["skills"]

    opencode = path(".config", "opencode", "skills", "forge")
    assert File.file?(File.join(opencode, "SKILL.md"))
    assert File.file?(File.join(opencode, ".forge-skill-generated"))
    config = JSON.parse(File.read(path(".config", "opencode", "opencode.jsonc")))
    assert_equal [path(".config", "opencode", "skills")], config.dig("skills", "paths")

    assert_includes @out.string, "bin      -> #{bin_link}"
  end

  it "is idempotent: a second run changes nothing and duplicates no config entry" do
    install!
    pi_before = File.read(path(".pi", "agent", "settings.json"))
    install!

    assert_equal File.join(repo, "bin", "forge"), File.readlink(bin_link)
    assert_equal pi_before, File.read(path(".pi", "agent", "settings.json"))
    config = JSON.parse(File.read(path(".config", "opencode", "opencode.jsonc")))
    assert_equal 1, config.dig("skills", "paths").size
  end

  it "refreshes a stale link that points elsewhere inside this repo" do
    FileUtils.mkdir_p(File.dirname(bin_link))
    File.symlink(File.join(repo, "bin", "old-forge"), bin_link)
    install!
    assert_equal File.join(repo, "bin", "forge"), File.readlink(bin_link)
  end

  it "refuses to replace a symlink to another forge, touching nothing" do
    FileUtils.mkdir_p(File.dirname(bin_link))
    File.symlink("/opt/other/forge", bin_link)

    error = assert_raises(Install::Refused) { install! }
    assert_includes error.message, "refusing to replace #{bin_link} (points to /opt/other/forge)"
    assert_equal "/opt/other/forge", File.readlink(bin_link)
    refute File.exist?(path(".claude", "skills", "forge"))
    refute File.exist?(path(".config", "opencode"))
  end

  it "refuses to replace a regular file" do
    FileUtils.mkdir_p(File.dirname(bin_link))
    File.write(bin_link, "#!/bin/sh\necho other\n")

    error = assert_raises(Install::Refused) { install! }
    assert_includes error.message, "refusing to replace #{bin_link}"
    assert_equal "#!/bin/sh\necho other\n", File.read(bin_link)
  end

  it "leaves an OpenCode skill dir it does not own alone" do
    foreign = path(".config", "opencode", "skills", "forge")
    FileUtils.mkdir_p(foreign)
    File.write(File.join(foreign, "SKILL.md"), "hand made\n")
    install!
    assert_equal "hand made\n", File.read(File.join(foreign, "SKILL.md"))
    refute File.exist?(File.join(foreign, ".forge-skill-generated"))
  end

  it "keeps existing Pi and OpenCode settings when registering" do
    FileUtils.mkdir_p(path(".pi", "agent"))
    File.write(path(".pi", "agent", "settings.json"), JSON.generate("skills" => ["/elsewhere"], "theme" => "dark"))
    FileUtils.mkdir_p(path(".config", "opencode"))
    File.write(path(".config", "opencode", "opencode.jsonc"), %({\n  "model": "x" // keep\n}\n))

    _out, err = capture_io { install! }

    pi = JSON.parse(File.read(path(".pi", "agent", "settings.json")))
    assert_equal ["/elsewhere", path(".claude", "skills")], pi["skills"]
    assert_equal "dark", pi["theme"]
    config = JSON.parse(File.read(path(".config", "opencode", "opencode.jsonc")))
    assert_equal "x", config["model"]
    assert_includes err, "has comments"
    assert File.file?(path(".config", "opencode", "opencode.jsonc.bak"))
  end
end
