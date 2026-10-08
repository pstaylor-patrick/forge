# frozen_string_literal: true

require_relative "error"

module ForgeCli
  # Typed-name confirmation for destructive writes. --yes skips it; without
  # --yes a non-TTY stdin is refused outright, so an agent or a pipe can never
  # confirm by accident. There is no environment-variable bypass.
  module Guard
    # confirm: {action: "overwrite the .env of example.com ...", token: "example.com"}
    def self.confirm!(confirm, yes:, stdin:, command:, out: $stderr)
      return if yes

      unless stdin.tty?
        raise GuardRefused, "#{command} is destructive and stdin is not a TTY; " \
                            "re-run with --yes to confirm, or -d to preview"
      end

      out.puts "This will #{confirm[:action]}. This cannot be undone."
      out.print "Type #{confirm[:token]} to confirm: "
      typed = stdin.gets.to_s.strip
      return if typed == confirm[:token].to_s

      raise Aborted, "confirmation did not match #{confirm[:token]}; nothing was changed"
    end
  end
end
