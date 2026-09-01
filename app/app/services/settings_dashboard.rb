class SettingsDashboard
  Stats = Struct.new(
    :services_total, :services_ready, :services_enabled,
    :total_disk_bytes, :total_disk_human, :active_region_count,
    keyword_init: true
  )

  def self.for(services:, active_regions:)
    new(services: services, active_regions: active_regions).stats
  end

  def initialize(services:, active_regions:)
    @services       = services
    @active_regions = active_regions
  end

  def stats
    total_bytes = @services.sum { |s| s.disk_bytes.to_i }
    Stats.new(
      services_total:      @services.size,
      services_ready:      @services.count { |s| s.status == "ready" },
      services_enabled:    @services.count(&:enabled),
      total_disk_bytes:    total_bytes,
      total_disk_human:    ActiveSupport::NumberHelper.number_to_human_size(total_bytes),
      active_region_count: @active_regions.size
    )
  end
end
