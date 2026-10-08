# frozen_string_literal: true

require_relative "spec_helper"
require "forge_cli/rate_limit"

describe ForgeCli::RateLimit do
  NOW = 1_800_000_000

  def wait(headers) = ForgeCli::RateLimit.wait_seconds(headers, now: NOW)

  it "prefers retry-after" do
    assert_equal 12, wait("retry-after" => "12", "x-ratelimit-reset" => (NOW + 50).to_s)
  end

  it "reads a large reset as an epoch timestamp" do
    assert_equal 25, wait("x-ratelimit-reset" => (NOW + 25).to_s)
  end

  it "never returns a negative wait for a past epoch reset" do
    assert_equal 0, wait("x-ratelimit-reset" => (NOW - 5).to_s)
  end

  it "reads a small reset as a delta in seconds" do
    assert_equal 17, wait("x-ratelimit-reset" => "17")
  end

  it "accepts a Time for now" do
    assert_equal 10, ForgeCli::RateLimit.wait_seconds({ "x-ratelimit-reset" => (NOW + 10).to_s }, now: Time.at(NOW))
  end

  it "defaults to 60 seconds without usable headers" do
    assert_equal 60, wait({})
    assert_equal 60, wait("retry-after" => "soon", "x-ratelimit-reset" => nil)
  end
end
