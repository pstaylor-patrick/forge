# frozen_string_literal: true

require "uri"

module ForgeCli
  # One HTTP call, described but not sent. Paths are relative to the API base.
  # query uses literal keys such as "page[size]"; the client URL-encodes them.
  Request = Data.define(:method, :path, :query, :body) do
    def initialize(method:, path:, query: {}, body: nil)
      super(method: method, path: path, query: query, body: body)
    end
  end

  # Pure request builders, one per Forge endpoint the CLI uses.
  module Endpoints
    module_function

    def user = get("/user")
    def orgs = get("/orgs")
    def servers(org) = get("#{org_path(org)}/servers")
    def server(org, server) = get(server_path(org, server))

    # -- helpers ------------------------------------------------------------

    def get(path, query = {}) = Request.new(method: "GET", path: path, query: query)

    def org_path(org) = "/orgs/#{segment(org)}"
    def server_path(org, server) = "#{org_path(org)}/servers/#{segment(server)}"

    def segment(value) = URI.encode_www_form_component(value.to_s)

    # Drops nil-valued keys, recursing into nested hashes, so optional
    # arguments never reach the API as explicit nulls.
    def compact_body(hash)
      hash.each_with_object({}) do |(key, value), out|
        value = compact_body(value) if value.is_a?(Hash)
        out[key] = value unless value.nil?
      end
    end
  end
end
