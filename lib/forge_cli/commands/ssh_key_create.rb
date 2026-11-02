# frozen_string_literal: true

require "forge_cli/command_support"
require "forge_cli/endpoints"
require "forge_cli/error"

module ForgeCli
  module Commands
    # forge ssh-key-create --name NAME (--key KEY | --key-file PATH) [--user USER] [-S SERVER]
    # Installs a public key for a server user. Not guarded: it removes nothing.
    class SshKeyCreate
      # A public key line: type, base64 body, optional comment. Private keys
      # (PEM blocks) never match, so one is never sent.
      PUBLIC_KEY = %r{\A(ssh-(ed25519|rsa|dss)|ecdsa-sha2-nistp\d+|sk-[a-z0-9@.-]+) [A-Za-z0-9+/]+={0,3}( \S.*)?\z}

      def self.run(argv, ctx:, formatter:)
        opts = { user: "forge" }
        parser = CommandSupport.parser(opts, banner: "ssh-key-create --name NAME (--key KEY | --key-file PATH) " \
                                                     "[--user USER] [-S SERVER] [-d]",
                                             write: true, server: true) do |o|
          o.on("--name NAME", "Key name") { |v| opts[:name] = v }
          o.on("--key KEY", "Public key line, e.g. 'ssh-ed25519 AAAA... comment'") { |v| opts[:key] = v }
          o.on("--key-file PATH", "File holding the public key (e.g. ~/.ssh/id_ed25519.pub)") { |v| opts[:key_file] = v }
          o.on("--user USER", "Server user the key is installed for (default forge)") { |v| opts[:user] = v }
        end
        CommandSupport.parse!(parser, argv, max_args: 0)
        name = opts[:name].to_s.strip
        raise Error, "--name is required\n#{parser.banner}" if name.empty?

        key = public_key(opts, parser)
        user = opts[:user].to_s.strip
        raise Error, "--user must not be empty" if user.empty?

        server = ctx.server(opts[:server])
        org = ctx.org
        request = Endpoints.create_ssh_key(org, server[:id], name: name, key: key, user: user)
        CommandSupport.write!(ctx, command: "ssh-key-create", request: request, opts: opts,
                                   affected: CommandSupport.server_affected(org, server[:id]),
                                   summary: lambda { |result|
                                     id = result.dig(:data, :id)
                                     "Added SSH key #{[id, "(#{name})"].compact.join(' ')} for #{user} on #{server[:name]}"
                                   })
      end

      def self.public_key(opts, parser)
        if opts[:key] && opts[:key_file]
          raise Error, "pass one of --key or --key-file, not both"
        elsif opts[:key_file]
          path = File.expand_path(opts[:key_file])
          raise Error, "--key-file not readable: #{opts[:key_file]}" unless File.file?(path) && File.readable?(path)

          key = File.read(path)
        elsif opts[:key]
          key = opts[:key]
        else
          raise Error, "one of --key or --key-file is required\n#{parser.banner}"
        end
        key = key.strip
        raise Error, "the key must be a single public key line (ssh-ed25519, ssh-rsa, ecdsa-..., sk-...)" unless key.match?(PUBLIC_KEY)

        key
      end
    end
  end
end
