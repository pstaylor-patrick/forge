# frozen_string_literal: true

require_relative "spec_helper"
require_relative "support/fake_client"
require "stringio"
require "forge_cli/commands/deploy"
require "forge_cli/endpoints"

describe "deploy --wait polling" do
  REQUEST = ForgeCli::Endpoints.deployment("my-org", 10, 20, 99)

  # Answers each poll with the next status (repeating the last); the sleeper
  # advances a fake clock instead of sleeping.
  def poll(statuses, timeout: 900)
    queue = statuses.dup
    client = FakeClient.new(fetch: { REQUEST.path => lambda { |_|
      status = queue.size > 1 ? queue.shift : queue.first
      { data: { id: "99", attributes: { status: status } } }
    } })
    now = 0
    slept = []
    err = StringIO.new
    result = ForgeCli::Commands::Deploy.wait(client, REQUEST, site_name: "example.com", id: "99", timeout: timeout,
                                                               sleeper: ->(s) { slept << s; now += s },
                                                               clock: -> { now }, err: err)
    [result, slept, err.string, client]
  ensure
    @client = client
  end

  it "returns the deployment when it finishes, printing each status change once" do
    result, slept, err = poll(%w[queued queued deploying deploying finished])
    assert_equal "finished", result.dig(:data, :attributes, :status)
    assert_equal [5, 5, 5, 5], slept
    assert_equal "deployment 99: queued\ndeployment 99: deploying\ndeployment 99: finished\n", err
  end

  it "returns at once when the first poll is already finished" do
    _, slept = poll(%w[finished])
    assert_empty slept
  end

  %w[failed failed-build cancelled].each do |status|
    it "raises DeployFailed when the deployment ends #{status}" do
      error = assert_raises(ForgeCli::DeployFailed) { poll(["deploying", status]) }
      assert_includes error.message, "ended #{status}"
      assert_includes error.message, "forge deploy-log example.com 99"
      assert_equal 2, @client.calls.size
    end
  end

  it "keeps polling through an unknown or missing status" do
    result, = poll([nil, "pending", "finished"])
    assert_equal "finished", result.dig(:data, :attributes, :status)
  end

  it "raises DeployFailed after the timeout without sleeping past it" do
    error = assert_raises(ForgeCli::DeployFailed) { poll(%w[deploying], timeout: 12) }
    assert_includes error.message, "still deploying after 12s"
    assert_includes error.message, "forge deploy-log example.com 99"
    # polls at t=0, 5, 10; the next would land at 15 > 12
    assert_equal 3, @client.calls.size
  end
end
