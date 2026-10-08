# frozen_string_literal: true

require "json"
require "uri"
require_relative "env_file"
require_relative "records"

module ForgeCli
  # The printable form of a request that a dry run did not send.
  module DryRun
    def self.describe(request, redact: nil)
      body = request.body
      body = redact.call(body) if redact && !body.nil?
      { method: request.method, path: request.path, query: request.query || {}, body: body }
    end

    def self.target(described)
      query = described[:query]
      query.empty? ? described[:path] : "#{described[:path]}?#{URI.encode_www_form(query)}"
    end
  end

  # JSON output (-j/--json): every command emits {ok: true, command:, data:}
  # with the raw API data, so output pipes cleanly to jq.
  module JsonFormatter
    def self.emit(command, data)
      puts JSON.pretty_generate({ ok: true, command: command, data: data })
    end

    def self.list(command, records, columns: nil, derive: nil) = emit(command, records)
    def self.show(command, record, fields: nil, derive: nil) = emit(command, record)
    def self.text(command, content, meta: {}, footer: []) = emit(command, { content: content, **meta })

    # A write that was not sent. redact: optional ->(body) { body } applied
    # before printing (masked env, hidden passwords).
    def self.dry_run(command, request, redact: nil)
      emit(command, { dry_run: true, request: DryRun.describe(request, redact: redact) })
    end

    # A write that was sent: the API data, or {done: true} for an empty response.
    def self.written(command, result, summary: nil)
      data = result.is_a?(Hash) ? result[:data] : nil
      emit(command, data || { done: true })
    end

    # A write skipped because it would change nothing.
    def self.unchanged(command, message = "no change")
      emit(command, { changed: false, message: message })
    end

    # Masked unless revealed: entries carry key names, and values only when
    # revealed. Raw content is included only when revealed.
    def self.env(command, site_name, content, revealed:)
      entries = EnvFile.entries(content).select { |e| e[:type] == :entry }
      if revealed
        emit(command, { site: site_name, revealed: true, content: content,
                        entries: entries.map { |e| { key: e[:key], value: e[:value] } } })
      else
        emit(command, { site: site_name, revealed: false,
                        entries: entries.map { |e| { key: e[:key], value: e[:value].empty? ? "" : EnvFile::MASK } } })
      end
    end
  end

  # Human output. Records arrive raw (JSON:API) and are flattened here.
  # A field missing from human output is a formatter bug: fix it here.
  # derive: optional ->(raw_record) { Hash } merged over the flattened row, for
  # columns the API nests or puts in relationships (server_id, commit summary).
  module Formatter
    RESET = "\e[0m"
    BOLD = "\e[1m"
    DIM = "\e[2m"

    # Count line, then aligned columns.
    def self.list(command, records, columns:, derive: nil)
      rows = records.map { |r| row(r, derive) }
      noun = rows.size == 1 ? command.sub(/s\z/, "") : command
      puts style("#{rows.size} #{noun}", DIM)
      return if rows.empty?

      header = columns.map(&:to_s)
      cells = rows.map { |row| columns.map { |c| cell(row[c]) } }
      widths = header.each_index.map { |i| ([header[i]] + cells.map { |c| c[i] }).map(&:length).max }
      puts style(align(header, widths), BOLD)
      cells.each { |c| puts align(c, widths) }
    end

    # "field: value" lines with aligned labels.
    def self.show(command, record, fields:, derive: nil)
      row = row(record, derive)
      width = fields.map { |f| f.to_s.length }.max.to_i + 1
      fields.each do |field|
        puts "#{style("#{field}:".ljust(width), DIM)} #{cell(row[field])}"
      end
    end

    # Verbatim content (logs, scripts) on stdout. footer: meta keys printed as
    # "key: value" on stderr, so stdout stays exactly the content.
    def self.text(command, content, meta: {}, footer: [])
      text = content.to_s
      print text
      puts unless text.empty? || text.end_with?("\n")
      footer.each { |key| $stderr.puts "#{key}: #{cell(meta[key])}" }
    end

    # The .env with values masked, or raw when revealed.
    def self.env(command, site_name, content, revealed:)
      text(command, revealed ? content : EnvFile.mask(content))
    end

    # DRY RUN header, the method and path (with query), and the body as
    # pretty JSON after redact.
    def self.dry_run(command, request, redact: nil)
      described = DryRun.describe(request, redact: redact)
      puts style("DRY RUN (nothing sent)", BOLD)
      puts "#{described[:method]} #{DryRun.target(described)}"
      puts "body: #{JSON.pretty_generate(described[:body])}" unless described[:body].nil?
    end

    # One line saying what changed, e.g. "Deployment 123 queued for example.com".
    def self.written(command, result, summary: nil)
      puts summary || "#{command}: done"
    end

    def self.unchanged(command, message = "no change")
      puts message
    end

    def self.row(record, derive)
      flat = Records.flatten(record)
      derive ? flat.merge(derive.call(record)) : flat
    end

    def self.cell(value)
      case value
      when nil then "-"
      when Array then value.empty? ? "-" : value.map { |v| cell(v) }.join(",")
      when Hash then JSON.generate(value)
      else value.to_s.gsub(/\s*\n\s*/, " ")
      end
    end

    def self.align(values, widths)
      values.each_with_index.map { |v, i| i == values.size - 1 ? v : v.ljust(widths[i]) }.join("  ")
    end

    def self.style(text, code)
      color? ? "#{code}#{text}#{RESET}" : text
    end

    def self.color?
      $stdout.tty? && ENV["NO_COLOR"].to_s.empty?
    end

    private_class_method :row, :align, :style, :color?
  end
end
