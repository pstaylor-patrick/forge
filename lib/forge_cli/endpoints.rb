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

    # -- sites ----------------------------------------------------------------
    # The org-wide site endpoints omit relationships unless asked; include=server
    # is what puts relationships.server on each record.

    def org_sites(org) = get("#{org_path(org)}/sites", { "include" => "server" })
    def org_site(org, site) = get("#{org_path(org)}/sites/#{segment(site)}", { "include" => "server" })
    def server_sites(org, server) = get("#{server_path(org, server)}/sites")

    # -- deployments ----------------------------------------------------------

    # Newest first. The API's default order is oldest first.
    def deployments(org, server, site, size:)
      get("#{site_path(org, server, site)}/deployments", { "sort" => "-created_at", "page[size]" => size })
    end

    def deployment(org, server, site, id) = get("#{site_path(org, server, site)}/deployments/#{segment(id)}")
    def deployment_log(org, server, site, id) = get("#{site_path(org, server, site)}/deployments/#{segment(id)}/log")
    def deployment_status(org, server, site) = get("#{site_path(org, server, site)}/deployments/status")
    def deploy_script(org, server, site) = get("#{site_path(org, server, site)}/deployments/script")

    # -- site resources -------------------------------------------------------

    def environment(org, server, site) = get("#{site_path(org, server, site)}/environment")
    def domains(org, server, site) = get("#{site_path(org, server, site)}/domains")
    def site_certificates(org, server, site) = get("#{site_path(org, server, site)}/certificates")

    SITE_LOG_TYPES = %w[application nginx-access nginx-error].freeze

    def site_log(org, server, site, type)
      raise ArgumentError, "unknown site log type: #{type}" unless SITE_LOG_TYPES.include?(type)

      get("#{site_path(org, server, site)}/logs/#{type}")
    end

    # -- server resources -----------------------------------------------------

    def schemas(org, server) = get("#{server_path(org, server)}/database/schemas")
    def db_users(org, server) = get("#{server_path(org, server)}/database/users")
    def daemons(org, server) = get("#{server_path(org, server)}/background-processes")
    def daemon_log(org, server, id) = get("#{server_path(org, server)}/background-processes/#{segment(id)}/log")
    def firewall_rules(org, server) = get("#{server_path(org, server)}/firewall-rules")
    def server_log(org, server, key) = get("#{server_path(org, server)}/logs/#{segment(key)}")

    def server_jobs(org, server) = get("#{server_path(org, server)}/scheduled-jobs")
    def site_jobs(org, server, site) = get("#{site_path(org, server, site)}/scheduled-jobs")
    def server_job_output(org, server, id) = get("#{server_path(org, server)}/scheduled-jobs/#{segment(id)}/output")

    def site_job_output(org, server, site, id)
      get("#{site_path(org, server, site)}/scheduled-jobs/#{segment(id)}/output")
    end

    # -- events ---------------------------------------------------------------

    def org_events(org, size:) = get("#{org_path(org)}/events", events_query(size))
    def server_events(org, server, size:) = get("#{server_path(org, server)}/events", events_query(size))
    def event_output(org, server, id) = get("#{server_path(org, server)}/events/#{segment(id)}/output")

    # -- writes: deploy, env, deploy script ----------------------------------

    # Queues a deployment; the API answers 202 with the DeploymentResource.
    def deploy(org, server, site) = write("POST", "#{site_path(org, server, site)}/deployments")

    # The request key is `environment`, though the read returns `content`.
    def put_environment(org, server, site, content:, cache: nil, queues: nil)
      write("PUT", "#{site_path(org, server, site)}/environment",
            { environment: content, cache: cache, queues: queues })
    end

    def put_deploy_script(org, server, site, content:, auto_source: nil)
      write("PUT", "#{site_path(org, server, site)}/deployments/script",
            { content: content, auto_source: auto_source })
    end

    # -- helpers ------------------------------------------------------------

    def get(path, query = {}) = Request.new(method: "GET", path: path, query: query)

    # A write request; nil body keys are dropped.
    def write(method, path, body = nil)
      Request.new(method: method, path: path, body: body && compact_body(body))
    end

    def org_path(org) = "/orgs/#{segment(org)}"
    def server_path(org, server) = "#{org_path(org)}/servers/#{segment(server)}"
    def site_path(org, server, site) = "#{server_path(org, server)}/sites/#{segment(site)}"

    # Newest first, one page of `size`.
    def events_query(size) = { "sort" => "-created_at", "page[size]" => size }

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
