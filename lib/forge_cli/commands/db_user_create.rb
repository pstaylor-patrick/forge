# frozen_string_literal: true

require "forge_cli/command_support"
require "forge_cli/endpoints"
require "forge_cli/error"
require "forge_cli/password"

module ForgeCli
  module Commands
    # forge db-user-create NAME [--databases a,b] [--read-only] [--password-stdin] [-S SERVER]
    # Creates a database user. The password is required and comes from
    # --password-stdin or a no-echo prompt, never argv; dry runs print it
    # masked. --databases names (or ids) resolve to ids. Not guarded.
    class DbUserCreate
      def self.run(argv, ctx:, formatter:, prompt: Password::CONSOLE)
        Password.reject_argv!(argv)
        opts = {}
        parser = CommandSupport.parser(opts, banner: "db-user-create NAME [--databases a,b] [--read-only] " \
                                                     "[--password-stdin] [-S SERVER] [-d]",
                                             write: true, server: true) do |o|
          o.on("--databases LIST", "Comma-separated database names or ids to grant access to") do |v|
            opts[:databases] = CommandSupport.name_list(v)
          end
          o.on("--read-only", "Grant read-only access") { opts[:read_only] = true }
          o.on(Password::FLAG, "Read the password from stdin (first line); otherwise prompted on a terminal") do
            opts[:password_stdin] = true
          end
        end
        name = CommandSupport.one_arg_quiet!(parser, argv, "NAME").strip
        raise Error, "NAME is empty" if name.empty?

        password = Password.read(opts, stdin: ctx.stdin, required: true, label: "Password for #{name}: ", prompt: prompt)
        server = ctx.server(opts[:server])
        org = ctx.org
        databases = opts[:databases] && ctx.schemas_named(server[:id], opts[:databases])
        request = Endpoints.create_db_user(org, server[:id], name: name, password: password,
                                                             database_ids: databases&.map { |d| Integer(d[:id]) },
                                                             read_only: opts[:read_only])
        CommandSupport.write!(ctx, command: "db-user-create", request: request, opts: opts,
                                   redact: Password.method(:redact),
                                   affected: CommandSupport.server_affected(org, server[:id]),
                                   summary: lambda { |result|
                                     id = result.dig(:data, :id)
                                     grants = databases ? " (databases: #{grant_names(databases)})" : ""
                                     "Created database user #{[id, "(#{name})"].compact.join(' ')} on #{server[:name]}#{grants}"
                                   })
      end

      def self.grant_names(databases) = databases.empty? ? "none" : databases.map { |d| d[:name] }.join(", ")

      private_class_method :grant_names
    end
  end
end
