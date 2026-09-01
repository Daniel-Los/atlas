module ControlPlane
  class PollStatusJob < ApplicationJob
    queue_as :default

    PROFILE_FOR = {
      "photon"      => "geocoding",
      "placeholder" => "geocoding",
      "libpostal"   => "geocoding",
      "valhalla"    => "routing",
      "overpass"    => "pois",
      "otp"         => "transit",
      "whosonfirst" => "data-setup"
    }.freeze

    def initialize(client: ControlPlaneClient.default)
      super()
      @client = client
    end

    def perform
      snapshot = @client.status
      Array(snapshot).each { |entry| sync(entry) }
      sync_update_statuses
    rescue ControlPlaneClient::Unavailable, ControlPlaneClient::BadResponse => e
      Rails.logger.warn("[PollStatusJob] sidecar #{e.class.name.demodulize}: #{e.message}")
    end

    private

    def sync(entry)
      name = entry["name"]
      service = Service.find_or_initialize_by(name: name) do |s|
        s.profile = PROFILE_FOR.fetch(name, "unknown")
      end

      attrs = {
        status:     map_status(entry),
        phase:      entry["phase"],
        progress:   entry["progress"],
        last_log:   entry["last_log_line"],
        disk_bytes: entry["disk_bytes"] || 0,
        last_seen_at: Time.current
      }

      changed = (service.attributes.slice(*attrs.keys.map(&:to_s)) != attrs.stringify_keys)
      service.assign_attributes(attrs)
      service.save!

      broadcast(service) if changed
    end

    def map_status(entry)
      return "ready" if entry["ready"]
      case entry["phase"]
      when nil, ""           then "unknown"
      when /download/i       then "downloading"
      when /build|merg|ingest|optimize|extract/i then "building"
      when /partial|stop/i   then "stopped"
      when /error|fail/i     then "error"
      when /unhealth/i       then "unhealthy"
      else "starting"
      end
    end

    def broadcast(service)
      Turbo::StreamsChannel.broadcast_replace_to(
        "services_channel",
        target: "service_#{service.name}",
        partial: "admin/services/service_card",
        locals: { service: service }
      )
    end

    # For each service marked as `running` in our DB, ask the sidecar whether
    # the run finished. On success → stamp dataset_updated_at + clear status.
    # On failure → record the error and silently disable auto-update.
    def sync_update_statuses
      Service.where(last_update_status: "running").find_each do |service|
        body = @client.update_status(service.name)
        case body["status"]
        when "success"
          service.finish_update!(success: true, duration_s: body["duration_s"])
          broadcast(service)
        when "failure"
          service.finish_update!(success: false, duration_s: body["duration_s"], error: body["error"])
          broadcast(service)
        end
      rescue ControlPlaneClient::Unavailable, ControlPlaneClient::BadResponse => e
        Rails.logger.warn("[PollStatusJob] update_status(#{service.name}): #{e.message}")
      end
    end
  end
end
