# frozen_string_literal: true

require "optparse"
require_relative "error"
require_relative "browser"
require_relative "guard"

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

    # The single required positional argument, or a usage error.
    def self.one_arg!(parser, argv, name)
      args = parse!(parser, argv, max_args: 1)
      raise Error, "missing #{name}\n#{parser.banner}" if args.empty?

      args.first
    end

    # The single required positional argument, with an error that does not
    # echo extra arguments (a password typed as one must not reach stderr).
    def self.one_arg_quiet!(parser, argv, name)
      args = parse!(parser, argv)
      raise Error, "missing #{name}\n#{parser.banner}" if args.empty?
      raise Error, "expected exactly one #{name} argument, got #{args.size}\n#{parser.banner}" if args.size > 1

      args.first
    end

    # Exactly the named positional arguments, in order, or a usage error.
    def self.args!(parser, argv, *names)
      args = parse!(parser, argv, max_args: names.size)
      raise Error, "missing #{names.drop(args.size).join(' and ')}\n#{parser.banner}" if args.size < names.size

      args
    end

    HOSTNAME = /\A([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\z/i

    # A domain name such as example.com, lowercased. Wildcards are a flag,
    # not part of the name. what names the argument in the error.
    def self.hostname!(value, what)
      name = value.to_s.strip.downcase
      return name if name.length <= 253 && name.match?(HOSTNAME)

      raise Error, "#{what} must be a domain name such as example.com, got '#{value}'"
    end

    # A comma-separated flag value as a list of names: blanks dropped, order
    # kept, duplicates removed.
    def self.name_list(value) = value.to_s.split(",").map(&:strip).reject(&:empty?).uniq

    # Parses a count flag value within min..max.
    def self.count(value, flag:, min: 1, max: nil)
      text = value.to_s.strip
      number = text.match?(/\A\d+\z/) ? text.to_i : nil
      if number.nil? || number < min || (max && number > max)
        range = max ? "#{min}..#{max}" : ">= #{min}"
        raise Error, "#{flag} must be an integer in #{range}, got '#{value}'"
      end
      number
    end

    # The one write path. Every write command calls this after resolving names
    # and building its request, so the order is fixed:
    #   dry-run exit -> guard -> perform -> print -> return Affected.
    # A dry run never prompts and never sends; it returns nil (no browser).
    #
    # confirm: nil for non-destructive writes, else {action:, token:} for Guard.
    # redact:  optional ->(body) { body } for dry-run output (env, passwords).
    # summary: optional ->(result) { "one line" } for human output.
    # A block, when given, receives the API result and returns the result to
    # print (deploy --wait polls there; env-set drops the response body).
    def self.write!(ctx, command:, request:, opts:, affected:, confirm: nil, redact: nil, summary: nil)
      if opts[:dry_run]
        ctx.formatter.dry_run(command, request, redact: redact)
        return nil
      end

      Guard.confirm!(confirm, yes: opts[:yes], stdin: ctx.stdin, command: command) if confirm
      result = ctx.client.perform(request)
      result = yield(result) if block_given?
      ctx.formatter.written(command, result, summary: summary&.call(result))
      affected
    end

    # The page a site-scoped write opens afterwards.
    def self.site_affected(org, ref) = Affected.new(org: org, server_id: ref[:server_id], site_id: ref[:site_id])

    # The page a server-scoped write opens afterwards.
    def self.server_affected(org, server_id) = Affected.new(org: org, server_id: server_id)

    # The server a server-scoped write targets, as {id:, name:, ...}, and the
    # site ref when --site is given. With --site, the site's own server is
    # used (-S only narrows the site lookup).
    def self.server_and_site(ctx, opts)
      return [ctx.server(opts[:server]), nil] unless opts[:site]

      ref = ctx.site(opts[:site], server_query: opts[:server])
      server = ctx.server(ref[:server_id].to_s)
      [server, ref]
    end

    # Fails unless value is one of allowed; flag names the option for the message.
    def self.one_of!(value, allowed, flag:)
      return value if allowed.include?(value)

      raise Error, "#{flag} must be one of #{allowed.join(', ')}, got '#{value}'"
    end

    # Guard prompt for a write that overwrites something on a site; the user
    # types the site name.
    def self.site_confirm(action, ref)
      { action: "#{action} of #{ref[:name]} (site #{ref[:site_id]} on server #{ref[:server_id]})", token: ref[:name] }
    end

    # Reads replacement content for --file PATH or --stdin.
    def self.read_source(opts, stdin, flag_help:)
      sources = %i[file stdin].select { |key| opts[key] }
      raise Error, "give exactly one of #{flag_help}" unless sources.size == 1

      if opts[:file]
        path = File.expand_path(opts[:file])
        raise Error, "no such file: #{opts[:file]}" unless File.file?(path)

        File.read(path)
      else
        stdin.read.to_s
      end
    end

    # Same text, ignoring trailing newlines (a file saved from the read
    # command gains one when the stored text lacks it).
    def self.same_text?(left, right)
      left.to_s.sub(/\n+\z/, "") == right.to_s.sub(/\n+\z/, "")
    end

    # The last n lines of content; n = 0 keeps everything.
    def self.tail(content, lines)
      text = content.to_s
      return text if lines.zero?

      text.lines.last(lines).join
    end
  end
end
