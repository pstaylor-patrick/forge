# frozen_string_literal: true

require "forge_cli/error"

# Answers fetch/fetch_all from canned bodies keyed by request path and records
# every call. perform records the request and returns a canned body (or {}).
# A canned value that responds to #call is called with the request each time,
# so a spec can answer a sequence (deploy --wait polling).
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
    answer(@fetch.fetch(request.path) { raise ForgeCli::NotFoundError, "no canned fetch for #{request.path}" }, request)
  end

  def fetch_all(request)
    @calls << [:fetch_all, request]
    answer(@fetch_all.fetch(request.path) { raise ForgeCli::NotFoundError, "no canned fetch_all for #{request.path}" }, request)
  end

  def perform(request)
    @performed << request
    answer(@perform.fetch(request.path, {}), request)
  end

  private

  def answer(value, request) = value.respond_to?(:call) ? value.call(request) : value
end
