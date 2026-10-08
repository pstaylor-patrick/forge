# frozen_string_literal: true

require "net/http"
require "openssl"
require "uri"
require "json"
require_relative "error"
require_relative "rate_limit"

module ForgeCli
  # HTTP for the Forge org-scoped API: auth, JSON, cursor pagination,
  # one wait-and-retry on 429, and status-to-error mapping.
  class Client
    DEFAULT_BASE = "https://forge.laravel.com/api"
    MAX_PAGES = 50
    PAGE_SIZE = 30
    MAX_RETRY_WAIT = 60
    NETWORK_ERRORS = [SocketError, Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EHOSTUNREACH,
                      Net::OpenTimeout, Net::ReadTimeout, OpenSSL::SSL::SSLError].freeze
    RATE_HEADERS = %w[retry-after x-ratelimit-limit x-ratelimit-remaining x-ratelimit-reset].freeze

    Response = Data.define(:status, :headers, :body, :raw)

    attr_reader :base

    # transport: ->(Net::HTTPRequest, URI) { response }, injectable for specs.
    #   The response needs #code, #body, and #[](header).
    # sleeper: ->(seconds) {}, injectable so specs never sleep.
    def initialize(token: ENV["FORGE_API_KEY"], base: ENV.fetch("FORGE_BASE_URL", DEFAULT_BASE),
                   transport: nil, sleeper: ->(seconds) { sleep(seconds) }, err: $stderr)
      if token.nil? || token.strip.empty?
        raise AuthError, "FORGE_API_KEY not set; symlink .env to the secrets store (see README)"
      end

      @token = token.strip
      @base = base.chomp("/")
      @transport = transport || method(:net_http)
      @sleeper = sleeper
      @err = err
    end

    # One request; returns the parsed body (symbolized Hash), {} on 204/empty.
    def fetch(request)
      call(request).body
    end

    # Writes: same as fetch, named separately so call sites read as intent.
    def perform(request)
      call(request).body
    end

    # GET every page, following meta.next_cursor; returns the records.
    def fetch_all(request)
      query = request.query.dup
      query["page[size]"] ||= PAGE_SIZE
      records = []
      pages = 0

      loop do
        response = call(request.with(query: query))
        pages += 1
        records.concat(Array(response.body[:data]))
        cursor = next_cursor(response.body)
        break unless cursor

        if pages >= MAX_PAGES
          @err.puts "forge: stopped after #{MAX_PAGES} pages; results are truncated"
          break
        end

        wait_for_window(response.headers)
        query = query.merge("page[cursor]" => cursor)
      end

      records
    end

    # Pure: maps a non-2xx status and raw body to an error.
    def self.error_for(status, raw)
      parsed = parse_json(raw)
      message = parsed.is_a?(Hash) ? parsed[:message].to_s : ""

      case status
      when 401 then AuthError.new("Forge rejected FORGE_API_KEY (401)", status: status, body: raw)
      when 403 then AuthError.new("token lacks permission for this action (403)", status: status, body: raw)
      when 404 then NotFoundError.new(message.empty? ? "resource not found (404)" : message, status: status, body: raw)
      when 429 then RateLimitError.new("rate limited (60 req/min)", status: status, body: raw)
      when 422 then ApiError.new(validation_message(parsed, message), status: status, body: raw)
      else ApiError.new(message.empty? ? "request failed" : message, status: status, body: raw)
      end
    end

    def self.validation_message(parsed, message)
      lines = [message.empty? ? "validation failed" : message]
      errors = parsed.is_a?(Hash) ? parsed[:errors] : nil
      if errors.is_a?(Hash)
        errors.each { |field, msgs| Array(msgs).each { |m| lines << "#{field}: #{m}" } }
      end
      lines.join("\n")
    end

    def self.parse_json(raw)
      JSON.parse(raw.to_s, symbolize_names: true)
    rescue JSON::ParserError
      nil
    end

    private_class_method :validation_message

    private

    def call(request)
      response = transmit(request)
      if response.status == 429 && (wait = RateLimit.wait_seconds(response.headers)) <= MAX_RETRY_WAIT
        # A 429 means the request was not processed, so retrying a write is safe.
        @err.puts "forge: rate limited, waiting #{wait + 1}s"
        @sleeper.call(wait + 1)
        response = transmit(request)
      end
      raise rate_limited(response) if response.status == 429
      raise self.class.error_for(response.status, response.raw) unless (200..299).cover?(response.status)

      response
    end

    def rate_limited(response)
      wait = RateLimit.wait_seconds(response.headers)
      RateLimitError.new("rate limited (60 req/min); resets in #{wait}s", status: 429, body: response.raw)
    end

    def transmit(request)
      uri = build_uri(request)
      http_request = build_http_request(request, uri)
      raw_response = @transport.call(http_request, uri)
      status = raw_response.code.to_i
      raw = raw_response.body.to_s
      headers = RATE_HEADERS.to_h { |name| [name, raw_response[name]] }
      Response.new(status: status, headers: headers, body: parse_body(status, raw), raw: raw)
    rescue *NETWORK_ERRORS => e
      raise Error, "network error talking to Forge: #{e.class}: #{e.message}"
    end

    def build_uri(request)
      url = "#{@base}#{request.path}"
      url += "?#{URI.encode_www_form(request.query)}" unless request.query.nil? || request.query.empty?
      URI(url)
    end

    def build_http_request(request, uri)
      klass = Net::HTTP.const_get(request.method.capitalize)
      http_request = klass.new(uri)
      http_request["Authorization"] = "Bearer #{@token}"
      http_request["Accept"] = "application/json"
      http_request["Content-Type"] = "application/json"
      http_request["User-Agent"] = "forge-cli"
      http_request.body = JSON.generate(request.body) unless request.body.nil?
      http_request
    end

    def parse_body(status, raw)
      return {} if status == 204 || raw.strip.empty?

      parsed = self.class.parse_json(raw)
      return parsed if parsed.is_a?(Hash)
      return { data: parsed } unless parsed.nil?

      { raw: raw }
    end

    def next_cursor(body)
      cursor = body.dig(:meta, :next_cursor)
      return cursor unless cursor.nil? || cursor.to_s.empty?

      # links is [] when empty (PHP serializes an empty map as a list), and a
      # link may be a bare string or {href:}.
      links = body[:links]
      next_link = links.is_a?(Hash) ? links[:next] : nil
      next_link = next_link[:href] if next_link.is_a?(Hash)
      return nil if next_link.nil? || next_link.to_s.empty?

      query = URI(next_link.to_s).query.to_s
      URI.decode_www_form(query).to_h["page[cursor]"]
    rescue URI::InvalidURIError
      nil
    end

    def wait_for_window(headers)
      return unless headers["x-ratelimit-remaining"].to_s.strip == "0"

      wait = RateLimit.wait_seconds(headers)
      @err.puts "forge: rate limit window used up, waiting #{wait + 1}s"
      @sleeper.call(wait + 1)
    end

    def net_http(http_request, uri)
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                                          open_timeout: 10, read_timeout: 30) do |http|
        http.request(http_request)
      end
    end
  end
end
