# frozen_string_literal: true

module ForgeCli
  # Helpers for JSON:API records ({id, type, attributes, relationships}).
  module Records
    module_function

    # {id:, **attributes}, with a numeric string id turned into an Integer.
    def flatten(record)
      return {} unless record.is_a?(Hash)

      { id: integer_id(record[:id]) }.merge(record[:attributes] || {})
    end

    # relationships.<name>.data.id, as an Integer when numeric.
    def rel_id(record, name)
      integer_id(record&.dig(:relationships, name.to_sym, :data, :id))
    end

    # "abc1234 first line of message" from attributes.commit, or nil.
    def dig_commit(record)
      commit = record&.dig(:attributes, :commit)
      return nil unless commit.is_a?(Hash)

      hash = commit[:hash].to_s[0, 7]
      message = commit[:message].to_s.lines.first.to_s.strip
      summary = [hash, message].reject(&:empty?).join(" ")
      summary.empty? ? nil : summary
    end

    def integer_id(value)
      value.is_a?(String) && value.match?(/\A\d+\z/) ? value.to_i : value
    end
  end
end
