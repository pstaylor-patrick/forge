# frozen_string_literal: true

module ForgeCli
  # Pure functions over the text of a .env file. Nothing here touches the
  # network or the filesystem.
  module EnvFile
    MASK = "********"
    ASSIGNMENT = /\A\s*(?<export>export\s+)?(?<key>[A-Za-z_][A-Za-z0-9_.]*)\s*=(?<rest>.*)\z/m
    COMMENTED_ASSIGNMENT = /\A\s*#\s*(?:export\s+)?(?<key>[A-Za-z_][A-Za-z0-9_.]*)\s*=(?<rest>.*)\z/m

    # One item per logical line, in order:
    #   {type: :entry, key:, value:, export:, raw_lines:}
    #   {type: :comment | :blank | :unparsed, raw_lines:}
    # A value that opens a quote not closed on the same line continues across
    # lines until the closing quote; the whole span is one entry. raw_lines
    # keep their line endings, so joining every item's raw_lines rebuilds the
    # input exactly.
    def self.entries(content)
      lines = content.to_s.lines
      items = []
      until lines.empty?
        line = lines.shift
        stripped = line.strip
        items <<
          if stripped.empty? then { type: :blank, raw_lines: [line] }
          elsif stripped.start_with?("#") then { type: :comment, raw_lines: [line] }
          elsif (match = ASSIGNMENT.match(line.chomp)) then entry(match, line, lines)
          else { type: :unparsed, raw_lines: [line] }
          end
      end
      items
    end

    # The file with every non-empty value replaced by a fixed-width mask:
    # blank lines stay blank, comments stay (a commented-out KEY=value is
    # masked too), KEY= with an empty value stays KEY=, a multi-line value
    # collapses to one masked line, and anything unparsable is hidden.
    def self.mask(content)
      out = entries(content).map do |item|
        case item[:type]
        when :blank then ""
        when :comment then mask_comment(item[:raw_lines].first.chomp)
        when :entry
          prefix = item[:export] ? "export " : ""
          item[:value].empty? ? "#{prefix}#{item[:key]}=" : "#{prefix}#{item[:key]}=#{MASK}"
        else "# (unparsed line hidden)"
        end
      end
      out.empty? ? "" : "#{out.join("\n")}\n"
    end

    # -- parsing helpers --------------------------------------------------------

    # One assignment, consuming continuation lines from `lines` while a quote
    # opened on the first line is still open.
    def self.entry(match, line, lines)
      raw_lines = [line]
      rest = match[:rest]
      while unclosed_quote?(rest) && !lines.empty?
        continuation = lines.shift
        raw_lines << continuation
        rest = "#{rest}\n#{continuation.chomp}"
      end
      { type: :entry, key: match[:key], value: parse_value(rest), export: !match[:export].nil?, raw_lines: raw_lines }
    end

    # For a value starting with a quote: [inner text, closed?]. Double quotes
    # honor \" and \\ escapes; single quotes have none. nil when unquoted.
    def self.scan_quoted(rest)
      value = rest.lstrip
      quote = value[0]
      return nil unless ['"', "'"].include?(quote)

      inner = +""
      escaped = false
      value[1..].to_s.each_char do |char|
        if escaped
          inner << (%w[" \\].include?(char) ? char : "\\#{char}")
          escaped = false
        elsif char == "\\" && quote == '"'
          escaped = true
        elsif char == quote
          return [inner, true]
        else
          inner << char
        end
      end
      [inner, false]
    end

    def self.unclosed_quote?(rest)
      quoted = scan_quoted(rest)
      !quoted.nil? && !quoted.last
    end

    # The value as the application sees it: the quoted text, or for an
    # unquoted value, trimmed and cut at an inline " #" comment.
    def self.parse_value(rest)
      quoted = scan_quoted(rest)
      quoted ? quoted.first : rest.sub(/\s+#.*\z/m, "").strip
    end

    def self.mask_comment(line)
      match = COMMENTED_ASSIGNMENT.match(line)
      return line.strip unless match

      parse_value(match[:rest]).empty? ? line.strip : "# #{match[:key]}=#{MASK}"
    end

    private_class_method :entry, :scan_quoted, :unclosed_quote?, :parse_value, :mask_comment
  end
end
