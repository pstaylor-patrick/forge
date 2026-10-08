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

    # -- writes: firewall, services, server actions --------------------------

    # port is a string (the API types it string|null, and allows ranges).
    # ip_address is a plain string: the snapshot's allOf narrows its first
    # part's untyped object to string, and RuleResource returns a string.
    def create_firewall_rule(org, server, name:, type:, port: nil, ip_address: nil)
      write("POST", "#{server_path(org, server)}/firewall-rules",
            { name: name, type: type, port: port&.to_s, ip_address: ip_address })
    end

    def delete_firewall_rule(org, server, id) = write("DELETE", "#{server_path(org, server)}/firewall-rules/#{segment(id)}")

    FIREWALL_TYPES = %w[allow deny].freeze

    # The actions the API accepts per service (one endpoint per service).
    SERVICE_ACTIONS = {
      "nginx" => %w[reboot stop],
      "mysql" => %w[reboot stop],
      "postgres" => %w[reboot stop],
      "redis" => %w[reboot],
      "supervisor" => %w[reboot],
      "php" => %w[reboot reload]
    }.freeze

    # version is required for php and ignored elsewhere.
    def service_action(org, server, service, action:, version: nil)
      unless SERVICE_ACTIONS.fetch(service, []).include?(action)
        raise ArgumentError, "unknown action #{action} for service #{service}"
      end

      write("POST", "#{server_path(org, server)}/services/#{segment(service)}/actions",
            { action: action, version: version })
    end

    SERVER_ACTIONS = %w[reboot power-cycle].freeze

    def server_action(org, server, action:)
      raise ArgumentError, "unknown server action: #{action}" unless SERVER_ACTIONS.include?(action)

      write("POST", "#{server_path(org, server)}/actions", { action: action })
    end

    # -- writes: background processes (daemons) ------------------------------

    DAEMON_USERS = %w[forge root].freeze

    def create_daemon(org, server, name:, command:, user:, processes:, directory: nil, site_id: nil,
                      startsecs: nil, stopwaitsecs: nil, stopsignal: nil)
      write("POST", "#{server_path(org, server)}/background-processes",
            { name: name, command: command, user: user, processes: processes, directory: directory,
              site_id: site_id, startsecs: startsecs, stopwaitsecs: stopwaitsecs, stopsignal: stopsignal })
    end

    def delete_daemon(org, server, id) = write("DELETE", "#{server_path(org, server)}/background-processes/#{segment(id)}")

    def daemon_action(org, server, id, action:)
      write("POST", "#{server_path(org, server)}/background-processes/#{segment(id)}/actions", { action: action })
    end

    # -- writes: scheduled jobs ------------------------------------------------

    JOB_FREQUENCIES = %w[minutely hourly nightly weekly monthly reboot custom].freeze

    def create_server_job(org, server, command:, user:, frequency:, name: nil, cron: nil, heartbeat: nil)
      write("POST", "#{server_path(org, server)}/scheduled-jobs",
            job_body(command: command, user: user, frequency: frequency, name: name, cron: cron, heartbeat: heartbeat))
    end

    def create_site_job(org, server, site, command:, user:, frequency:, name: nil, cron: nil, heartbeat: nil)
      write("POST", "#{site_path(org, server, site)}/scheduled-jobs",
            job_body(command: command, user: user, frequency: frequency, name: name, cron: cron, heartbeat: heartbeat))
    end

    def delete_server_job(org, server, id) = write("DELETE", "#{server_path(org, server)}/scheduled-jobs/#{segment(id)}")

    def delete_site_job(org, server, site, id)
      write("DELETE", "#{site_path(org, server, site)}/scheduled-jobs/#{segment(id)}")
    end

    # -- writes: database schemas and users -----------------------------------
    # The API has no PUT for schemas; "update" applies to database users only.

    # user and password create a user alongside the database (password is
    # only used when user is given).
    def create_schema(org, server, name:, user: nil, password: nil)
      write("POST", "#{server_path(org, server)}/database/schemas", { name: name, user: user, password: password })
    end

    def delete_schema(org, server, id) = write("DELETE", "#{server_path(org, server)}/database/schemas/#{segment(id)}")

    def create_db_user(org, server, name:, password:, database_ids: nil, read_only: nil)
      write("POST", "#{server_path(org, server)}/database/users",
            { name: name, password: password, database_ids: database_ids, read_only: read_only })
    end

    # database_ids replaces the user's grants; nil leaves them alone.
    def update_db_user(org, server, id, password: nil, database_ids: nil)
      write("PUT", "#{server_path(org, server)}/database/users/#{segment(id)}",
            { password: password, database_ids: database_ids })
    end

    def delete_db_user(org, server, id) = write("DELETE", "#{server_path(org, server)}/database/users/#{segment(id)}")

    # -- writes: sites --------------------------------------------------------

    SITE_TYPES = %w[laravel symfony statamic wordpress phpmyadmin php nextjs nuxtjs static-html other custom].freeze
    PHP_VERSIONS = %w[php5 php56-old php56 php70 php71 php72 php73 php74 php80 php81 php82 php83 php84 php85].freeze
    WWW_REDIRECT_TYPES = %w[from-www to-www none].freeze
    # The snapshot also lists gitlab-custom and custom, which need a
    # source_control_provider_id the CLI does not take.
    SOURCE_CONTROL_PROVIDERS = %w[github gitlab bitbucket].freeze

    # Open question 7: domain_mode is "custom" (the site answers on name, a
    # domain you own) or "on-forge" (a Forge-provided subdomain). The CLI
    # creates custom-domain sites only, so name is always the domain.
    CREATE_SITE_KEYS = %i[php_version web_directory source_control_provider repository branch is_isolated isolated_user
                          zero_downtime_deployments allow_wildcard_subdomains www_redirect_type].freeze

    def create_site(org, server, type:, name:, **attrs)
      check_site_keys!(attrs, CREATE_SITE_KEYS)

      write("POST", "#{server_path(org, server)}/sites", { type: type, name: name, domain_mode: "custom", **attrs })
    end

    UPDATE_SITE_KEYS = %i[php_version type directory root_path repository_branch push_to_deploy
                          deployment_retention].freeze

    def update_site(org, server, site, **attrs)
      check_site_keys!(attrs, UPDATE_SITE_KEYS)

      write("PUT", site_path(org, server, site), attrs)
    end

    def delete_site(org, server, site) = write("DELETE", site_path(org, server, site))

    # -- writes: domains and certificates -------------------------------------

    # The API requires all three keys.
    def create_domain(org, server, site, name:, www_redirect_type:, allow_wildcard_subdomains:)
      write("POST", "#{site_path(org, server, site)}/domains",
            { name: name, www_redirect_type: www_redirect_type, allow_wildcard_subdomains: allow_wildcard_subdomains })
    end

    def delete_domain(org, server, site, id) = write("DELETE", "#{site_path(org, server, site)}/domains/#{segment(id)}")

    def domain_certificates(org, server, site, domain_id)
      get("#{site_path(org, server, site)}/domains/#{segment(domain_id)}/certificates")
    end

    CERT_VERIFICATION_METHODS = %w[http-01 dns-01].freeze
    CERT_KEY_TYPES = %w[ecdsa rsa].freeze

    # Let's Encrypt only. The request's `enable` is not sent: the snapshot says
    # it is ignored for Let's Encrypt certificates.
    def issue_certificate(org, server, site, domain_id, verification_method:, key_type:)
      write("POST", "#{site_path(org, server, site)}/domains/#{segment(domain_id)}/certificates",
            { type: "letsencrypt", letsencrypt: { verification_method: verification_method, key_type: key_type } })
    end

    def delete_certificate(org, server, site, domain_id, id)
      write("DELETE", "#{site_path(org, server, site)}/domains/#{segment(domain_id)}/certificates/#{segment(id)}")
    end

    # -- helpers ------------------------------------------------------------

    def job_body(command:, user:, frequency:, name:, cron:, heartbeat:)
      { command: command, user: user, frequency: frequency, name: name, cron: cron, heartbeat: heartbeat }
    end

    def check_site_keys!(attrs, allowed)
      unknown = attrs.keys - allowed
      raise ArgumentError, "unknown site attribute: #{unknown.join(', ')}" unless unknown.empty?
    end

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
