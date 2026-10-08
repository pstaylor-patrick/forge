# frozen_string_literal: true

require_relative "spec_helper"
require "forge_cli/resolver"

describe ForgeCli::Resolver do
  RECORDS = [
    { id: 1, name: "web-1" },
    { id: 2, name: "Web-2" },
    { id: 3, name: "worker" },
    { id: 4, name: "worker" },
    { id: 5, name: "404" }
  ].freeze

  def pick(query) = ForgeCli::Resolver.pick(RECORDS, query, kind: "server")

  it "matches a numeric query against ids" do
    assert_equal "Web-2", pick("2")[:name]
    assert_equal "web-1", pick(1)[:name]
  end

  it "falls back to names when a numeric query matches no id" do
    assert_equal 5, pick("404")[:id]
  end

  it "prefers an exact name match" do
    assert_equal 1, pick("web-1")[:id]
  end

  it "matches names case-insensitively when nothing matches exactly" do
    assert_equal 2, pick("web-2")[:id]
  end

  it "does not match partial names" do
    assert_raises(ForgeCli::NotFoundError) { pick("web") }
  end

  it "lists available names when nothing matches" do
    error = assert_raises(ForgeCli::NotFoundError) { pick("nope") }
    assert_includes error.message, "no server matches 'nope'"
    assert_includes error.message, "web-1, worker"
  end

  it "lists ids when several records match" do
    error = assert_raises(ForgeCli::AmbiguousError) { pick("worker") }
    assert_includes error.message, "3  worker"
    assert_includes error.message, "4  worker"
  end

  it "resolves by another key" do
    orgs = [{ id: 9, slug: "my-org" }]
    assert_equal 9, ForgeCli::Resolver.pick(orgs, "my-org", kind: "org", key: :slug)[:id]
  end
end
