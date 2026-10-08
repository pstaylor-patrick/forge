# frozen_string_literal: true

require_relative "spec_helper"
require "forge_cli/browser"

describe ForgeCli::Browser do
  B = ForgeCli::Browser

  def affected(site_id: nil) = ForgeCli::Affected.new(org: "my-org", server_id: 10, site_id: site_id)

  it "opens the site page for a site-scoped write" do
    assert_equal ["https://forge.laravel.com/servers/10/sites/20"], B.urls(affected(site_id: 20))
  end

  it "opens the server page for a server-scoped write" do
    assert_equal ["https://forge.laravel.com/servers/10"], B.urls(affected)
  end

  it "accepts numeric string ids" do
    value = ForgeCli::Affected.new(org: "my-org", server_id: "10", site_id: "20")
    assert_equal ["https://forge.laravel.com/servers/10/sites/20"], B.urls(value)
  end

  it "has no url for nothing" do
    assert_equal [], B.urls(nil)
  end

  it "launches each url unless FORGE_NO_BROWSER is set" do
    opened = []
    launcher = ->(url) { opened << url }
    B.open(affected(site_id: 20), env: {}, launcher: launcher)
    assert_equal ["https://forge.laravel.com/servers/10/sites/20"], opened

    B.open(affected(site_id: 20), env: { "FORGE_NO_BROWSER" => "1" }, launcher: launcher)
    B.open(nil, env: {}, launcher: launcher)
    assert_equal 1, opened.size
  end

  it "treats an empty FORGE_NO_BROWSER as unset" do
    refute B.suppressed?({ "FORGE_NO_BROWSER" => "" })
    assert B.suppressed?({ "FORGE_NO_BROWSER" => "1" })
  end
end
