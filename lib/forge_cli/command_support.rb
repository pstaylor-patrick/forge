# frozen_string_literal: true

require "optparse"
require_relative "error"

module ForgeCli
  # Shared option parsing for commands. The reserved short flags (-S, -d, -y,
  # and the global -j) are defined here and nowhere else.
  module CommandSupport
    # Returns an OptionParser writing into opts. server: adds -S/--server;
    # write: adds -d/--dry-run; destructive: adds -y/--yes. A block can add
    # command-specific options.
    def self.parser(opts, banner:, write: false, destructive: false, server: false)
      OptionParser.new do |o|
        o.banner = "Usage: forge #{banner}"
        o.on("-S", "--server NAME_OR_ID", "Server name or id (default: FORGE_SERVER, else the only server)") { |v| opts[:server] = v } if server
        o.on("-d", "--dry-run", "Print the request without sending it") { opts[:dry_run] = true } if write
        o.on("-y", "--yes", "Confirm a destructive change without the typed-name prompt") { opts[:yes] = true } if destructive
        yield o if block_given?
      end
    end

    # Parses argv in place; returns the positional arguments. Bad flags become
    # ForgeCli::Error (exit 1). max_args caps the positional count.
    def self.parse!(parser, argv, max_args: nil)
      rest = parser.parse(argv)
      if max_args && rest.size > max_args
        raise Error, "unexpected argument: #{rest[max_args]}\n#{parser.banner}"
      end

      rest
    rescue OptionParser::ParseError => e
      raise Error, "#{e.message}\n#{parser.banner}"
    end
  end
end
