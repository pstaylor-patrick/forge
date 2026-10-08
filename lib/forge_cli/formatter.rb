# frozen_string_literal: true

require "json"
require_relative "records"

module ForgeCli
  # JSON output (-j/--json): every command emits {ok: true, command:, data:}
  # with the raw API data, so output pipes cleanly to jq.
  module JsonFormatter
    def self.emit(command, data)
      puts JSON.pretty_generate({ ok: true, command: command, data: data })
    end

    def self.list(command, records, columns: nil) = emit(command, records)
    def self.show(command, record, fields: nil) = emit(command, record)
    def self.text(command, content, meta: {}) = emit(command, { content: content, **meta })
  end

  # Human output. Records arrive raw (JSON:API) and are flattened here.
  # A field missing from human output is a formatter bug: fix it here.
  module Formatter
    RESET = "\e[0m"
    BOLD = "\e[1m"
    DIM = "\e[2m"

    # Count line, then aligned columns.
    def self.list(command, records, columns:)
      rows = records.map { |r| Records.flatten(r) }
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
    def self.show(command, record, fields:)
      row = Records.flatten(record)
      width = fields.map { |f| f.to_s.length }.max.to_i + 1
      fields.each do |field|
        puts "#{style("#{field}:".ljust(width), DIM)} #{cell(row[field])}"
      end
    end

    # Verbatim content (logs, scripts).
    def self.text(command, content, meta: {})
      text = content.to_s
      print text
      puts unless text.empty? || text.end_with?("\n")
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

    private_class_method :align, :style, :color?
  end
end
