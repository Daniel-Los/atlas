require "fugit"

module ControlPlane
  # Runs on the recurring schedule (see config/recurring.yml). For each service
  # with auto_update_enabled, checks whether its cron expression has matched at
  # any point since the last scheduler tick. If so, kicks off an update via the
  # sidecar. On any failure, Service#finish_update! silently disables the toggle
  # per the kill-switch contract.
  class AutoUpdateScanJob < ApplicationJob
    queue_as :default

    # Used as the "previous tick" baseline when a service has no recorded
    # last_update_check_at yet — assume we just woke up.
    DEFAULT_LOOKBACK = 1.day

    def initialize(client: ControlPlaneClient.default, now: Time.current)
      super()
      @client = client
      @now    = now
    end

    def perform
      Service.auto_updating.find_each do |service|
        next unless service.auto_update_armed?
        next unless due?(service)

        attempt(service)
      end
    end

    private

    def due?(service)
      schedule = service.effective_schedule
      return false if schedule.blank?
      # @continuous services self-update via diff streams; the scheduled run
      # is informational only — skip kicking off a sidecar call.
      return false if schedule == DatasetRegistry::Entry::CONTINUOUS

      cron = Fugit.parse_cron(schedule)
      return false if cron.nil?

      last = service.last_update_check_at || (@now - DEFAULT_LOOKBACK)
      cron.next_time(last).to_local_time <= @now
    end

    def attempt(service)
      return unless service.begin_update!
      entry = service.dataset_entry
      return service.finish_update!(success: false, error: "no dataset entry") unless entry

      @client.update!(service.name, update_kind: entry.update_kind)
    rescue ControlPlaneClient::Unavailable, ControlPlaneClient::BadResponse => e
      service.finish_update!(success: false, error: e.message)
    end
  end
end
