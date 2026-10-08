# frozen_string_literal: true

require_relative "error"

module ForgeCli
  # Name-or-id resolution over flattened records. No partial matching.
  module Resolver
    # A numeric query matches an id exactly. Otherwise (or when no id matches)
    # an exact name match wins, then a case-insensitive exact match.
    # Zero matches raise NotFoundError listing what exists; several raise
    # AmbiguousError listing "id  name" for each.
    def self.pick(records, query, kind:, key: :name)
      query = query.to_s.strip
      matches = by_id(records, query)
      matches = records.select { |r| r[key].to_s == query } if matches.empty?
      matches = records.select { |r| r[key].to_s.casecmp?(query) } if matches.empty?

      case matches.size
      when 1 then matches.first
      when 0 then raise NotFoundError, not_found_message(records, query, kind, key)
      else raise AmbiguousError, ambiguous_message(matches, query, kind, key)
      end
    end

    def self.by_id(records, query)
      return [] unless query.match?(/\A\d+\z/)

      records.select { |r| r[:id].to_s == query }
    end

    def self.not_found_message(records, query, kind, key)
      names = records.map { |r| r[key] }.compact.map(&:to_s).sort
      available = names.empty? ? "none" : names.join(", ")
      "no #{kind} matches '#{query}' (available: #{available})"
    end

    def self.ambiguous_message(matches, query, kind, key)
      lines = matches.map { |r| "  #{r[:id]}  #{r[key]}" }
      "'#{query}' matches several #{kind}s; pass the id:\n#{lines.join("\n")}"
    end

    private_class_method :by_id, :not_found_message, :ambiguous_message
  end
end
