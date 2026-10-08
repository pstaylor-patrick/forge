# frozen_string_literal: true

require "rbconfig"

module ForgeCli
  # What a successful write touched: the org, the server, and (for site-scoped
  # writes) the site. Write commands return one; dry runs and no-ops return nil.
  Affected = Data.define(:org, :server_id, :site_id) do
    def initialize(org:, server_id:, site_id: nil)
      super
    end
  end

  # No write is silent: bin/forge opens the affected Forge page after every
  # successful write command, from one place. FORGE_NO_BROWSER=1 suppresses it
  # (headless, CI, scripts). Dry runs never get here.
  module Browser
    SITE_URL = "https://forge.laravel.com/servers/%<server_id>d/sites/%<site_id>d"
    SERVER_URL = "https://forge.laravel.com/servers/%<server_id>d"

    def self.open(affected, env: ENV, launcher: method(:launch))
      return if affected.nil? || suppressed?(env)

      urls(affected).each { |url| launcher.call(url) }
    end

    # Pure: the page for a write's affected value. Site-scoped writes open the
    # site; server-scoped writes (and site deletion) open the server.
    def self.urls(affected)
      return [] if affected.nil? || affected.server_id.nil?

      ids = { server_id: Integer(affected.server_id), site_id: affected.site_id && Integer(affected.site_id) }
      [format(affected.site_id ? SITE_URL : SERVER_URL, ids)]
    end

    def self.suppressed?(env = ENV)
      !env["FORGE_NO_BROWSER"].to_s.strip.empty?
    end

    def self.launch(url)
      case RbConfig::CONFIG["host_os"]
      when /darwin/ then system("open", url, out: File::NULL, err: File::NULL)
      when /mswin|mingw|cygwin/ then system("cmd", "/c", "start", "", url, out: File::NULL, err: File::NULL)
      else system("xdg-open", url, out: File::NULL, err: File::NULL)
      end
    end
  end
end
