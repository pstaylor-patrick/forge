#!/usr/bin/env ruby
# frozen_string_literal: true

# Installs the forge CLI and the /forge skill from this repo. The repo is the
# source of truth: edit bin/forge or skills/forge/SKILL.md here, then re-run
# this script. Targets:
#
#   PATH        -> symlink ~/.local/bin/forge at <repo>/bin/forge, refusing to
#                  replace a forge binary that belongs to anything else
#                  (for example Laravel's official forge CLI)
#   Claude Code -> symlink ~/.claude/skills/forge at the repo source
#   Pi          -> register ~/.claude/skills as a skills root in its settings
#                  (Pi reads the dir, so the symlink above is enough once listed)
#   OpenCode    -> copy the skill into ~/.config/opencode/skills/forge (OpenCode
#                  does not follow symlinks) and list that dir in opencode.jsonc
#
# The OpenCode copy carries its own marker, distinct from other installers',
# so installers never prune each other's generated skills.

require "json"
require "fileutils"

module Install
  SKILL_NAME      = "forge"
  BIN_NAME        = "forge"
  OPENCODE_MARKER = ".forge-skill-generated"

  # Raised when the install would clobber something it does not own.
  class Refused < StandardError; end

  class Installer
    def initialize(repo:, home:, out: $stdout)
      @repo = File.realpath(repo)
      @home = home
      @out = out
    end

    def run
      raise Refused, "skill source not found: #{source}" unless File.file?(File.join(source, "SKILL.md"))
      raise Refused, "binary not found: #{bin_source}" unless File.file?(bin_source)

      # The bin link goes first: if it refuses, nothing else has been touched.
      link_bin
      link_claude
      register_pi
      mirror_opencode
      report
    end

    private

    def source               = File.join(@repo, "skills", SKILL_NAME)
    def bin_source           = File.join(@repo, "bin", BIN_NAME)
    def bin_dir              = File.join(@home, ".local", "bin")
    def bin_link             = File.join(bin_dir, BIN_NAME)
    def claude_skills_root   = File.join(@home, ".claude", "skills")
    def claude_link          = File.join(claude_skills_root, SKILL_NAME)
    def pi_settings          = File.join(@home, ".pi", "agent", "settings.json")
    def opencode_config      = File.join(@home, ".config", "opencode", "opencode.jsonc")
    def opencode_skills_root = File.join(@home, ".config", "opencode", "skills")
    def opencode_skill       = File.join(opencode_skills_root, SKILL_NAME)

    # Create or refresh ~/.local/bin/forge. Only a missing entry or a symlink
    # that already points into this repo is ours to replace; a regular file, a
    # directory, or a symlink elsewhere is someone else's forge and stays put.
    def link_bin
      FileUtils.mkdir_p(bin_dir)
      if File.symlink?(bin_link)
        target = link_target(bin_link)
        unless inside_repo?(target)
          raise Refused, "refusing to replace #{bin_link} (points to #{target}); remove it or install manually"
        end

        File.delete(bin_link)
      elsif File.exist?(bin_link)
        raise Refused, "refusing to replace #{bin_link} (a #{File.ftype(bin_link)}, not a symlink into " \
                       "#{@repo}); remove it or install manually"
      end
      File.symlink(bin_source, bin_link)
    end

    # The symlink's target as an absolute path, resolved through any symlinked
    # directories when it exists, so /var vs /private/var style aliases compare
    # equal. A dangling target is expanded relative to the link's directory.
    def link_target(link)
      target = File.expand_path(File.readlink(link), File.dirname(link))
      File.exist?(target) ? File.realpath(target) : target
    end

    def inside_repo?(path) = path == @repo || path.start_with?("#{@repo}/")

    # Rebuild the link every run so a stray hand-placed copy or an older link is
    # replaced. rm_rf on a symlink drops only the link; on a real directory (a
    # prior non-symlinked install) it clears the way for the symlink.
    def link_claude
      FileUtils.mkdir_p(claude_skills_root)
      FileUtils.rm_rf(claude_link)
      FileUtils.ln_s(source, claude_link)
    end

    def register_pi
      data = load_json(pi_settings)
      roots = Array(data["skills"])
      return if roots.include?(claude_skills_root)

      data["skills"] = roots + [claude_skills_root]
      write_json(pi_settings, data)
    end

    def mirror_opencode
      copy_opencode_skill
      register_opencode_path
    end

    # Only overwrite a copy we own (carries our marker) or a fresh slot, so a
    # hand-made or other-installer dir of the same name is left untouched.
    def copy_opencode_skill
      return if File.exist?(opencode_skill) && !File.exist?(File.join(opencode_skill, OPENCODE_MARKER))

      FileUtils.rm_rf(opencode_skill)
      FileUtils.mkdir_p(opencode_skills_root)
      FileUtils.cp_r(source, opencode_skill)
      File.write(File.join(opencode_skill, OPENCODE_MARKER), "source: #{source}\n")
    end

    def register_opencode_path
      data = load_json(opencode_config)
      skills = data["skills"].is_a?(Hash) ? data["skills"] : {}
      paths = Array(skills["paths"])
      return if paths.include?(opencode_skills_root)

      warn_if_comments(opencode_config)
      skills["paths"] = paths + [opencode_skills_root]
      data["skills"] = skills
      write_json(opencode_config, data)
    end

    # write_json reserializes as plain JSON, so any comments in a .jsonc file are
    # dropped. Announce that before it happens (the .bak still has the original)
    # rather than letting the loss be silent. Detect comments by what strip_jsonc
    # removes, not by a parse failure: JSON.parse tolerates comments on some Ruby
    # versions, so a failed parse is not a reliable signal.
    def warn_if_comments(path)
      return unless File.exist?(path)

      raw = File.read(path)
      warn "note: #{path} has comments; rewriting drops them (original saved to #{path}.bak)" if strip_jsonc(raw) != raw
    end

    def load_json(path)
      return {} unless File.exist?(path)

      raw = File.read(path)
      JSON.parse(raw)
    rescue JSON::ParserError
      # Tolerate JSONC comments; refuse to silently discard a config we cannot
      # parse, since persisting {} would erase the user's settings.
      begin
        JSON.parse(strip_jsonc(raw))
      rescue JSON::ParserError
        raise Refused, "cannot parse #{path}; fix or remove it, then re-run"
      end
    end

    def write_json(path, data)
      FileUtils.mkdir_p(File.dirname(path))
      FileUtils.cp(path, "#{path}.bak") if File.exist?(path)
      tmp = "#{path}.tmp"
      File.write(tmp, "#{JSON.pretty_generate(data)}\n")
      File.rename(tmp, path)
    end

    # Strip // line and /* block */ comments, leaving comment-like sequences
    # inside string literals intact (a backslash escapes the next character).
    def strip_jsonc(text)
      out = +""
      i = 0
      in_string = false
      while i < text.length
        c = text[i]
        if in_string
          out << c
          if c == "\\" && i + 1 < text.length
            out << text[i + 1]
            i += 2
            next
          end
          in_string = false if c == '"'
          i += 1
        elsif c == '"'
          in_string = true
          out << c
          i += 1
        elsif c == "/" && text[i + 1] == "/"
          i += 2
          i += 1 while i < text.length && text[i] != "\n"
        elsif c == "/" && text[i + 1] == "*"
          i += 2
          i += 1 until i >= text.length || (text[i] == "*" && text[i + 1] == "/")
          i += 2
        else
          out << c
          i += 1
        end
      end
      out
    end

    def report
      @out.puts "forge installed:"
      @out.puts "  bin      -> #{bin_link} -> #{bin_source}"
      @out.puts "  claude   -> #{claude_link} -> #{source}"
      @out.puts "  pi       -> #{pi_settings} (skills root #{claude_skills_root})"
      @out.puts "  opencode -> #{opencode_skill}"
      return if ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).include?(bin_dir)

      @out.puts "note: #{bin_dir} is not on PATH; add it to run forge by name"
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  begin
    Install::Installer.new(repo: __dir__, home: Dir.home).run
  rescue Install::Refused => e
    abort "install: #{e.message}"
  end
end
