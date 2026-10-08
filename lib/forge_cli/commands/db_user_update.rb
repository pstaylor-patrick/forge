# frozen_string_literal: true

require "forge_cli/command_support"
require "forge_cli/endpoints"
require "forge_cli/error"
require "forge_cli/password"

module ForgeCli
  module Commands
    # forge db-user-update USER [--databases a,b] [--password-stdin] [-S SERVER]
    # Changes a database user's password and/or grants. --databases REPLACES
    # the user's grants with exactly that list. The new password comes from
    # --password-stdin (prompted without echo when stdin is a terminal), never
    # argv; dry runs print it masked. Not guarded.
    class DbUserUpdate
      def self.run(argv, ctx:, formatter:, prompt: Password::CONSOLE)
        Password.reject_argv!(argv)
        opts = {}
        parser = CommandSupport.parser(opts, banner: "db-user-update USER [--databases a,b] [--password-stdin] " \
                                                     "[-S SERVER] [-d]",
                                             write: true, server: true) do |o|
          o.on("--databases LIST", "Replace the user's grants with these database names or ids " \
                                   "(comma-separated; '' removes every grant)") do |v|
            opts[:databases] = CommandSupport.name_list(v)
          end
          o.on(Password::FLAG, "Set a new password read from stdin (prompted without echo on a terminal)") do
            opts[:password_stdin] = true
          end
        end
        query = CommandSupport.one_arg_quiet!(parser, argv, "USER")
        unless opts[:databases] || opts[:password_stdin]
          raise Error, "give --databases, #{Password::FLAG}, or both\n#{parser.banner}"
        end

        password = Password.read(opts, stdin: ctx.stdin, required: false, label: "New password: ", prompt: prompt)
        server = ctx.server(opts[:server])
        org = ctx.org
        user = ctx.db_user(server[:id], query)
        databases = opts[:databases] && ctx.schemas_named(server[:id], opts[:databases])
        request = Endpoints.update_db_user(org, server[:id], user[:id], password: password,
                                                                        database_ids: databases&.map { |d| Integer(d[:id]) })
        label = "#{user[:id]} (#{user[:name]})"
        CommandSupport.write!(ctx, command: "db-user-update", request: request, opts: opts,
                                   redact: Password.method(:redact),
                                   affected: CommandSupport.server_affected(org, server[:id]),
                                   summary: ->(_) { "Updated database user #{label} on #{server[:name]}: #{changes(password, databases)}" })
      end

      def self.changes(password, databases)
        parts = []
        parts << "password changed" if password
        parts << "databases set to #{databases.empty? ? 'none' : databases.map { |d| d[:name] }.join(', ')}" if databases
        parts.join("; ")
      end

      private_class_method :changes
    end
  end
end
