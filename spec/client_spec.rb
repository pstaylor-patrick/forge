# frozen_string_literal: true

require_relative "spec_helper"
require "json"
require "stringio"
require "forge_cli/client"
require "forge_cli/endpoints"

# Stands in for Net::HTTPResponse: #code, #body, and #[](header).
FakeResponse = Struct.new(:code, :body, :headers) do
  def [](name) = (headers || {})[name.downcase]
end

describe ForgeCli::Client do
  def json(status, payload, headers = {}) = FakeResponse.new(status.to_s, JSON.generate(payload), headers)

  # responses: consumed in order; every sent request is recorded.
  def client_with(*responses)
    @sent = []
    @slept = []
    @err = StringIO.new
    queue = responses.dup
    transport = lambda do |request, uri|
      @sent << [request, uri]
      queue.shift or raise "unexpected request #{request.method} #{uri}"
    end
    ForgeCli::Client.new(token: "test-token", base: "https://forge.test/api",
                         transport: transport, sleeper: ->(s) { @slept << s }, err: @err)
  end

  def page(ids, next_cursor: nil, headers: {})
    json(200, { data: ids.map { |i| { id: i.to_s, type: "servers", attributes: { name: "web-#{i}" } } },
                links: [], meta: { next_cursor: next_cursor } }, headers)
  end

  describe "construction" do
    it "raises AuthError without a token" do
      assert_raises(ForgeCli::AuthError) { ForgeCli::Client.new(token: nil) }
      error = assert_raises(ForgeCli::AuthError) { ForgeCli::Client.new(token: "  ") }
      assert_includes error.message, "FORGE_API_KEY not set"
    end
  end

  describe "#fetch" do
    it "sends auth and JSON headers and parses a symbolized body" do
      client = client_with(json(200, { data: { id: "1", attributes: { name: "Dev" } } }))
      body = client.fetch(ForgeCli::Endpoints.user)
      request, uri = @sent.first
      assert_equal "https://forge.test/api/user", uri.to_s
      assert_equal "GET", request.method
      assert_equal "Bearer test-token", request["Authorization"]
      assert_equal "application/json", request["Accept"]
      assert_equal "Dev", body.dig(:data, :attributes, :name)
    end

    it "encodes query brackets" do
      client = client_with(json(200, { data: [] }))
      client.fetch(ForgeCli::Endpoints.get("/orgs", { "page[size]" => 5 }))
      assert_equal "https://forge.test/api/orgs?page%5Bsize%5D=5", @sent.first[1].to_s
    end

    it "sends a JSON body when the request has one" do
      client = client_with(FakeResponse.new("202", "", {}))
      client.perform(ForgeCli::Request.new(method: "POST", path: "/x", body: { action: "reboot" }))
      request = @sent.first[0]
      assert_equal "POST", request.method
      assert_equal({ "action" => "reboot" }, JSON.parse(request.body))
    end

    it "returns {} for 204 and empty bodies" do
      client = client_with(FakeResponse.new("204", nil, {}), FakeResponse.new("200", "  ", {}))
      assert_equal({}, client.perform(ForgeCli::Request.new(method: "DELETE", path: "/x")))
      assert_equal({}, client.fetch(ForgeCli::Endpoints.user))
    end

    it "keeps a non-JSON 2xx body as raw text" do
      client = client_with(FakeResponse.new("200", "plain log line\n", {}))
      assert_equal({ raw: "plain log line\n" }, client.fetch(ForgeCli::Endpoints.user))
    end

    it "wraps network failures in ForgeCli::Error" do
      client = ForgeCli::Client.new(token: "t", base: "https://forge.test/api",
                                    transport: ->(_r, _u) { raise SocketError, "getaddrinfo failed" })
      error = assert_raises(ForgeCli::Error) { client.fetch(ForgeCli::Endpoints.user) }
      assert_includes error.message, "network error talking to Forge"
    end

    it "raises the mapped error for a non-2xx response" do
      client = client_with(json(404, { message: "Not Found." }))
      error = assert_raises(ForgeCli::NotFoundError) { client.fetch(ForgeCli::Endpoints.server("my-org", 1)) }
      assert_equal "Not Found.", error.message
    end
  end

  describe ".error_for" do
    def error(status, payload = {}) = ForgeCli::Client.error_for(status, JSON.generate(payload))

    it "maps 401 and 403 to AuthError" do
      assert_instance_of ForgeCli::AuthError, error(401)
      assert_includes error(401).message, "401"
      assert_instance_of ForgeCli::AuthError, error(403)
      assert_includes error(403).message, "lacks permission"
    end

    it "maps 404 to NotFoundError" do
      assert_instance_of ForgeCli::NotFoundError, error(404)
    end

    it "maps 429 to RateLimitError, an ApiError" do
      assert_instance_of ForgeCli::RateLimitError, error(429)
      assert_kind_of ForgeCli::ApiError, error(429)
    end

    it "assembles a 422 message from message and errors" do
      e = error(422, { message: "The given data was invalid.", errors: { name: ["The name field is required."], port: ["Too big.", "Not a number."] } })
      assert_instance_of ForgeCli::ApiError, e
      assert_equal 422, e.status
      assert_equal "The given data was invalid.\nname: The name field is required.\nport: Too big.\nport: Not a number.", e.message
    end

    it "maps other statuses to ApiError and keeps the raw body" do
      e = ForgeCli::Client.error_for(500, "<html>oops</html>")
      assert_instance_of ForgeCli::ApiError, e
      assert_equal 500, e.status
      assert_equal "<html>oops</html>", e.body
    end
  end

  describe "#fetch_all" do
    it "follows meta.next_cursor and concatenates data" do
      client = client_with(page([1, 2], next_cursor: "abc"), page([3]))
      records = client.fetch_all(ForgeCli::Endpoints.servers("my-org"))
      assert_equal %w[1 2 3], records.map { |r| r[:id] }
      first_query = URI.decode_www_form(@sent[0][1].query).to_h
      second_query = URI.decode_www_form(@sent[1][1].query).to_h
      assert_equal({ "page[size]" => "30" }, first_query)
      assert_equal({ "page[size]" => "30", "page[cursor]" => "abc" }, second_query)
    end

    it "keeps a page size the request already sets" do
      client = client_with(page([1]))
      client.fetch_all(ForgeCli::Endpoints.get("/orgs", { "page[size]" => 5 }))
      assert_equal({ "page[size]" => "5" }, URI.decode_www_form(@sent[0][1].query).to_h)
    end

    it "falls back to the cursor in links.next" do
      second = json(200, { data: [{ id: "2" }], links: {}, meta: {} })
      first = json(200, { data: [{ id: "1" }], links: { next: "https://forge.test/api/orgs?page%5Bcursor%5D=xyz" }, meta: {} })
      client = client_with(first, second)
      assert_equal %w[1 2], client.fetch_all(ForgeCli::Endpoints.orgs).map { |r| r[:id] }
      assert_equal "xyz", URI.decode_www_form(@sent[1][1].query).to_h["page[cursor]"]
    end

    it "stops after MAX_PAGES with a truncation warning" do
      pages = Array.new(ForgeCli::Client::MAX_PAGES) { |i| page([i], next_cursor: "c#{i}") }
      client = client_with(*pages)
      records = client.fetch_all(ForgeCli::Endpoints.orgs)
      assert_equal ForgeCli::Client::MAX_PAGES, records.size
      assert_equal ForgeCli::Client::MAX_PAGES, @sent.size
      assert_includes @err.string, "truncated"
    end

    it "waits for the window when remaining is 0 and another page is needed" do
      client = client_with(page([1], next_cursor: "n", headers: { "x-ratelimit-remaining" => "0", "x-ratelimit-reset" => "7" }), page([2]))
      client.fetch_all(ForgeCli::Endpoints.orgs)
      assert_equal [8], @slept
    end
  end

  describe "rate limiting" do
    it "waits and retries a 429 once" do
      client = client_with(json(429, { message: "Too Many Attempts." }, { "retry-after" => "3" }),
                           json(200, { data: { id: "1" } }))
      body = client.fetch(ForgeCli::Endpoints.user)
      assert_equal "1", body.dig(:data, :id)
      assert_equal [4], @slept
      assert_equal 2, @sent.size
      assert_includes @err.string, "rate limited, waiting 4s"
    end

    it "raises RateLimitError when the retry is also limited" do
      client = client_with(json(429, {}, { "retry-after" => "2" }), json(429, {}, { "retry-after" => "9" }))
      error = assert_raises(ForgeCli::RateLimitError) { client.fetch(ForgeCli::Endpoints.user) }
      assert_includes error.message, "resets in 9s"
      assert_equal 2, @sent.size
      assert_equal [3], @slept
    end

    it "raises without waiting when the reset is more than 60 seconds away" do
      client = client_with(json(429, {}, { "retry-after" => "120" }))
      assert_raises(ForgeCli::RateLimitError) { client.fetch(ForgeCli::Endpoints.user) }
      assert_empty @slept
      assert_equal 1, @sent.size
    end
  end
end
