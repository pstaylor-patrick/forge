# frozen_string_literal: true

require_relative "spec_helper"
require "forge_cli/records"

describe ForgeCli::Records do
  R = ForgeCli::Records

  RECORD = {
    id: "123",
    type: "sites",
    attributes: {
      name: "example.com",
      commit: { hash: "abcdef0123456789", author: "dev", message: "Fix the thing\n\nLonger body", branch: "main" }
    },
    relationships: { server: { data: { type: "servers", id: "42" } } }
  }.freeze

  it "flattens id and attributes, converting numeric ids" do
    flat = R.flatten(RECORD)
    assert_equal 123, flat[:id]
    assert_equal "example.com", flat[:name]
  end

  it "keeps non-numeric ids as strings" do
    assert_equal "abc", R.flatten({ id: "abc", attributes: {} })[:id]
  end

  it "flattens a record without attributes" do
    assert_equal({ id: 7 }, R.flatten({ id: "7" }))
    assert_equal({}, R.flatten(nil))
  end

  it "reads a relationship id" do
    assert_equal 42, R.rel_id(RECORD, :server)
    assert_nil R.rel_id(RECORD, :latestDeployment)
    assert_nil R.rel_id({ id: "1" }, :server)
  end

  it "summarizes a commit as short hash plus first message line" do
    assert_equal "abcdef0 Fix the thing", R.dig_commit(RECORD)
  end

  it "returns nil when there is no commit" do
    assert_nil R.dig_commit({ attributes: { commit: nil } })
    assert_nil R.dig_commit({ attributes: { commit: { hash: nil, message: nil } } })
  end
end
