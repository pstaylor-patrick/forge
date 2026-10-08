# frozen_string_literal: true

require "forge_cli/command_support"
require "forge_cli/endpoints"
require "forge_cli/env_file"
require "forge_cli/error"

module ForgeCli
  module Commands
    # forge env-set SITE (--file PATH | --stdin | --set KEY=VALUE... --unset KEY...)
    # Replaces the site's .env. Destructive (it overwrites the file), so it
    # takes the typed-name guard or --yes. Prints only key names, never values;
    # the dry-run body is masked unless --reveal.
    class EnvSet
      MODES = "--file PATH, --stdin, or --set KEY=VALUE / --unset KEY"

      def self.run(argv, ctx:, formatter:, err: $stderr)
        opts = { edits: [] }
        parser = CommandSupport.parser(opts, banner: "env-set SITE (--file PATH | --stdin | --set KEY=VALUE | " \
                                                     "--unset KEY)... [--cache] [--queues] [--reveal] [-S SERVER] [-d] [-y]",
                                             write: true, destructive: true, server: true) do |o|
          o.on("--file PATH", "Replace the .env with this file") { |v| opts[:file] = v }
          o.on("--stdin", "Replace the .env with stdin (needs --yes: stdin is not a TTY)") { opts[:stdin] = true }
          o.on("--set KEY=VALUE", "Set one key (repeatable; applied in order)") { |v| opts[:edits] << [:set, v] }
          o.on("--unset KEY", "Remove one key (repeatable; applied in order)") { |v| opts[:edits] << [:unset, v] }
          o.on("--cache", "Ask Forge to cache the config after saving") { opts[:cache] = true }
          o.on("--queues", "Ask Forge to restart queues after saving") { opts[:queues] = true }
          o.on("--reveal", "Show raw values in the dry-run body") { opts[:reveal] = true }
        end
        query = CommandSupport.one_arg!(parser, argv, "SITE")
        mode_count = [opts[:file], opts[:stdin], opts[:edits].empty? ? nil : true].compact.size
        raise Error, "give exactly one of #{MODES}\n#{parser.banner}" unless mode_count == 1

        edits = opts[:edits].map { |kind, arg| parse_edit(kind, arg) }
        replacement = edits.empty? ? read_replacement(opts, ctx) : nil
        ref = ctx.site(query, server_query: opts[:server])
        org = ctx.org
        current = ctx.client.fetch(Endpoints.environment(org, ref[:server_id], ref[:site_id]))
                     .dig(:data, :attributes, :content).to_s
        updated = replacement || apply(current, edits)

        if updated == current || (edits.empty? && CommandSupport.same_text?(updated, current))
          formatter.unchanged("env-set")
          return nil
        end

        err.puts diff_lines(EnvFile.key_diff(current, updated))
        request = Endpoints.put_environment(org, ref[:server_id], ref[:site_id], content: updated,
                                                                                 cache: opts[:cache], queues: opts[:queues])
        CommandSupport.write!(
          ctx, command: "env-set", request: request, opts: opts, redact: opts[:reveal] ? nil : method(:mask_body),
               affected: CommandSupport.site_affected(org, ref),
               confirm: CommandSupport.site_confirm("overwrite the .env", ref),
               summary: ->(_) { "Updated .env for #{ref[:name]}" }
        ) { |_result| {} } # never echo the response: it could carry the file
      end

      def self.mask_body(body) = body.merge(environment: EnvFile.mask(body[:environment]))

      def self.parse_edit(kind, arg)
        if kind == :set
          key, value = arg.split("=", 2)
          raise Error, "--set needs KEY=VALUE, got '#{arg}'" if value.nil?
        else
          key = arg
        end
        raise Error, "invalid env key '#{key}'" unless EnvFile.valid_key?(key)

        [kind, key, value]
      end

      def self.apply(content, edits)
        edits.reduce(content) do |text, (kind, key, value)|
          kind == :set ? EnvFile.set(text, key, value) : EnvFile.unset(text, key)
        end
      end

      def self.read_replacement(opts, ctx)
        CommandSupport.read_source(opts, ctx.stdin, flag_help: MODES)
      end

      # Key names only. Comment or formatting changes show as no key changes.
      def self.diff_lines(diff)
        lines = %i[added removed changed].filter_map do |kind|
          "keys #{kind}: #{diff[kind].join(', ')}" unless diff[kind].empty?
        end
        lines.empty? ? "keys unchanged (comments or formatting differ)" : lines.join("\n")
      end

      private_class_method :mask_body, :parse_edit, :apply, :read_replacement, :diff_lines
    end
  end
end
