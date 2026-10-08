# frozen_string_literal: true

require "io/console"
require_relative "error"

module ForgeCli
  # Database passwords come from stdin (--password-stdin) or a no-echo
  # terminal prompt, never from argv, and dry runs print them masked.
  module Password
    MASK = "********"
    MAX_LENGTH = 255
    FLAG = "--password-stdin"

    # Reads from the controlling terminal without echo. Returns nil when there
    # is no terminal.
    CONSOLE = ->(label) { IO.console&.getpass(label) }

    # Fails, without echoing anything, on an argument that looks like a
    # password passed on the command line: --password, --password=..., or
    # --password-stdin=... OptionParser would otherwise abbreviate --password
    # to --password-stdin, or echo "--password=VALUE" in its error message.
    def self.reject_argv!(argv)
      bad = argv.take_while { |arg| arg != "--" }.find do |arg|
        arg.start_with?("--pass") && arg != FLAG
      end
      return unless bad

      raise Error, "passwords are never taken as arguments; pipe one to #{FLAG}, or run on a terminal to be prompted"
    end

    # The password for a write, or nil when none is wanted.
    #
    # stdin: the command's stdin. With --password-stdin, the first line is the
    #   password (when stdin is a terminal, it is prompted for without echo).
    #   Without it, a terminal is prompted when the password is required.
    # required: whether the write needs one (raise when none can be had).
    # dry_run: a dry run never prompts; the body carries MASK instead, and the
    #   dry-run output masks it anyway.
    # prompt: ->(label) { String or nil }, injectable for specs.
    def self.read(opts, stdin:, required:, label: "Password: ", prompt: CONSOLE)
      if opts[:password_stdin]
        value = stdin.tty? ? ask(opts, prompt, label) : stdin.gets.to_s.chomp
      elsif required && stdin.tty?
        value = ask(opts, prompt, label)
      elsif required
        raise Error, "a password is required: pipe it to #{FLAG}, or run on a terminal to be prompted"
      else
        return nil
      end
      validate!(value)
    end

    # The body with its password masked, for dry-run output.
    def self.redact(body) = body.key?(:password) ? body.merge(password: MASK) : body

    def self.ask(opts, prompt, label)
      return MASK if opts[:dry_run]

      value = prompt.call(label)
      raise Error, "no terminal to prompt for a password; pipe it to #{FLAG}" if value.nil?

      value.chomp
    end

    def self.validate!(value)
      raise Error, "the password is empty" if value.to_s.empty?
      raise Error, "the password is longer than #{MAX_LENGTH} characters" if value.length > MAX_LENGTH

      value
    end

    private_class_method :ask, :validate!
  end
end
