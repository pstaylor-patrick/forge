# frozen_string_literal: true

require "forge_cli/error"

# Answers fetch/fetch_all from canned bodies keyed by request path and records
# every call. perform records the request and returns a canned body (or {}).
class FakeClient
  attr_reader :calls, :performed

  def initialize(fetch: {}, fetch_all: {}, perform: {})
    @fetch = fetch
    @fetch_all = fetch_all
    @perform = perform
    @calls = []
    @performed = []
  end

  def fetch(request)
    @calls << [:fetch, request]
    @fetch.fetch(request.path) { raise ForgeCli::NotFoundError, "no canned fetch for #{request.path}" }
  end

  def fetch_all(request)
    @calls << [:fetch_all, request]
    @fetch_all.fetch(request.path) { raise ForgeCli::NotFoundError, "no canned fetch_all for #{request.path}" }
  end

  def perform(request)
    @performed << request
    @perform.fetch(request.path, {})
  end
end
