class Service < ApplicationRecord
  UPDATE_STATUSES = %w[running success failure].freeze

  enum :status, {
    unknown:     0,
    stopped:     1,
    starting:    2,
    downloading: 3,
    building:    4,
    ready:       5,
    error:       6,
    unhealthy:   7
  }

  validates :name,    presence: true, uniqueness: true
  validates :profile, presence: true
  validates :progress, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }, allow_nil: true
  validates :disk_bytes, numericality: { greater_than_or_equal_to: 0 }
  validates :last_update_status, inclusion: { in: UPDATE_STATUSES }, allow_nil: true

  scope :auto_updating, -> { where(auto_update_enabled: true) }

  def dataset_entry
    DatasetRegistry.default[name]
  end

  def effective_schedule
    return update_schedule_cron if update_schedule_cron.present?
    dataset_entry&.default_schedule
  end

  def freshness_label
    return "Never updated" unless dataset_updated_at
    "Updated on #{dataset_updated_at.utc.strftime('%Y-%m-%d, %H:%M')} UTC"
  end

  def update_running? = last_update_status == "running"
  def update_failed?  = last_update_status == "failure"
  def disk_impact_summary = dataset_entry&.disk_impact_summary || "Unknown"

  def auto_update_armed?
    auto_update_enabled && !update_running? && !update_failed?
  end

  def begin_update!
    transaction do
      lock!
      return false if update_running?
      update!(last_update_check_at: Time.current, last_update_status: "running", last_update_error: nil)
      true
    end
  end

  def finish_update!(success:, duration_s: nil, error: nil)
    if success
      update!(
        last_update_status: "success",
        last_update_duration_s: duration_s,
        last_update_error: nil,
        dataset_updated_at: Time.current
      )
    else
      # Failure kill-switch: silently disables auto-update — admin must re-arm via Update now.
      update!(
        last_update_status: "failure",
        last_update_duration_s: duration_s,
        last_update_error: error.to_s.truncate(2000),
        auto_update_enabled: false
      )
    end
  end
end
