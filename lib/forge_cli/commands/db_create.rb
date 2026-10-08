# frozen_string_literal: true

require "forge_cli/command_support"
require "forge_cli/endpoints"
require "forge_cli/error"
require "forge_cli/password"

module ForgeCli
  module Commands
    # forge db-create NAME [--user USER] [--password-stdin] [-S SERVER]
    # Creates a database schema, and with --user a database user for it. The
    # user's password comes from --password-stdin or a no-echo prompt, never
    # argv, and dry runs print it masked. Not guarded.
    class DbCreate
      MAX_NAME = 63

      def self.run(argv, ctx:, formatter:, prompt: Password::CONSOLE)
        Password.reject_argv!(argv)
        opts = {}
        parser = CommandSupport.parser(opts, banner: "db-create NAME [--user USER] [--password-stdin] [-S SERVER] [-d]",
                                             write: true, server: true) do |o|
          o.on("--user USER", "Also create this database user (its password is prompted for, or read from stdin)") do |v|
            opts[:user] = v
          end
          o.on(Password::FLAG, "Read the --user password from stdin (first line)") { opts[:password_stdin] = true }
        end
        name = CommandSupport.one_arg_quiet!(parser, argv, "NAME").strip
        raise Error, "NAME must be at most #{MAX_NAME} characters (got #{name.length})" if name.length > MAX_NAME

        user = opts[:user]&.strip
        raise Error, "--user is empty" if user && user.empty?
        raise Error, "#{Password::FLAG} only applies with --user" if opts[:password_stdin] && !user

        password = user ? Password.read(opts, stdin: ctx.stdin, required: true, label: "Password for #{user}: ", prompt: prompt) : nil
        server = ctx.server(opts[:server])
        org = ctx.org
        request = Endpoints.create_schema(org, server[:id], name: name, user: user, password: password)
        CommandSupport.write!(ctx, command: "db-create", request: request, opts: opts,
                                   redact: Password.method(:redact),
                                   affected: CommandSupport.server_affected(org, server[:id]),
                                   summary: lambda { |result|
                                     id = result.dig(:data, :id)
                                     with_user = user ? " with user #{user}" : ""
                                     "Created database #{[id, "(#{name})"].compact.join(' ')}#{with_user} on #{server[:name]}"
                                   })
      end
    end
  end
end
