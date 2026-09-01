class ControlPlaneClient
  class Error < StandardError; end
  class Unavailable < Error; end
  class BadResponse < Error; end

  def self.default
    new(connection: build_default_connection)
  end

  def initialize(connection:)
    @conn = connection
  end

  def status
    response = @conn.get("/status")
    raise BadResponse, "#{response.status} from sidecar" unless response.success?
    response.body
  rescue Faraday::ConnectionFailed, Faraday::TimeoutError => e
    raise Unavailable, e.message
  end

  def tiles_status
    response = @conn.get("/tiles/status")
    raise BadResponse, "#{response.status} from sidecar /tiles/status" unless response.success?
    response.body
  rescue Faraday::ConnectionFailed, Faraday::TimeoutError => e
    raise Unavailable, e.message
  end

  def logs(name, tail: 200)
    response = @conn.get("/logs/#{name}", { tail: tail })
    raise BadResponse, "#{response.status} from sidecar at /logs/#{name}" unless response.success?
    response.body.is_a?(String) ? response.body : response.body.to_s
  rescue Faraday::ConnectionFailed, Faraday::TimeoutError => e
    raise Unavailable, e.message
  end

  def enable!(name);  post!("/actions/services/#{name}/enable"); end
  def disable!(name); post!("/actions/services/#{name}/disable"); end

  # Kicks off an asynchronous update on the sidecar. Returns true on 202;
  # raises Unavailable / BadResponse on transport or 5xx errors. Caller is
  # responsible for marking the Service row as running before this call.
  def update!(name, update_kind:)
    post!("/actions/services/#{name}/update", { update_kind: update_kind })
  end

  # Polls the sidecar for the current state of an in-flight update. Returns a
  # hash with at minimum a "status" key ("idle" | "running" | "success" | "failure")
  # plus, when not idle, "kind", "started_at", "finished_at", "duration_s", "error".
  def update_status(name)
    response = @conn.get("/actions/services/#{name}/update")
    raise BadResponse, "#{response.status} from sidecar update status" unless response.success?
    response.body
  rescue Faraday::ConnectionFailed, Faraday::TimeoutError => e
    raise Unavailable, e.message
  end

  def apply_regions(names)
    post!("/actions/regions", { regions: names })
  end

  def download_tiles!(url)
    post!("/actions/tiles", { url: url })
  end

  def self.build_default_connection
    base = ENV.fetch("CONTROL_PLANE_URL", "http://atlas-control:8090")
    Faraday.new(url: base) do |b|
      b.request :json
      b.response :json, content_type: /\bjson$/
      b.options.timeout = ENV.fetch("CONTROL_PLANE_TIMEOUT", 60).to_i
      b.options.open_timeout = ENV.fetch("CONTROL_PLANE_OPEN_TIMEOUT", 5).to_i
    end
  end

  private

  def post!(path, body = nil)
    response =
      if body
        @conn.post(path, JSON.generate(body), "Content-Type" => "application/json")
      else
        @conn.post(path)
      end
    raise BadResponse, "#{response.status} from sidecar at #{path}" unless response.success?
    true
  rescue Faraday::ConnectionFailed, Faraday::TimeoutError => e
    raise Unavailable, e.message
  end
end
