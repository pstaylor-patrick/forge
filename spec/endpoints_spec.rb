# frozen_string_literal: true

require_relative "spec_helper"
require "forge_cli/endpoints"

describe ForgeCli::Endpoints do
  E = ForgeCli::Endpoints

  it "builds the account and org reads" do
    assert_equal ForgeCli::Request.new(method: "GET", path: "/user"), E.user
    assert_equal "/orgs", E.orgs.path
    assert_equal({}, E.orgs.query)
    assert_nil E.orgs.body
  end

  it "builds server paths under the org" do
    assert_equal "/orgs/my-org/servers", E.servers("my-org").path
    assert_equal "/orgs/my-org/servers/42", E.server("my-org", 42).path
    assert_equal "GET", E.server("my-org", 42).method
  end

  it "encodes path segments built from names" do
    assert_equal "/orgs/my+org%2Fx/servers", E.servers("my org/x").path
  end

  it "keeps query keys literal so the client can encode the brackets" do
    request = E.get("/orgs", { "page[size]" => 30 })
    assert_equal({ "page[size]" => 30 }, request.query)
    assert_equal "page%5Bsize%5D=30", URI.encode_www_form(request.query)
  end

  it "drops nil body keys, including nested ones" do
    body = E.compact_body({ a: 1, b: nil, c: { d: nil, e: "x" }, f: false })
    assert_equal({ a: 1, c: { e: "x" }, f: false }, body)
  end

  it "defaults query to {} and body to nil on Request" do
    request = ForgeCli::Request.new(method: "POST", path: "/x")
    assert_equal({}, request.query)
    assert_nil request.body
    assert_equal({ k: 1 }, request.with(body: { k: 1 }).body)
  end
end
