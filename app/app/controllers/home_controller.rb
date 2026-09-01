class HomeController < ApplicationController
  DEGRADED_STATUSES = %w[error unhealthy stopped].freeze

  def index
    @tiles_url    = Setting.get("tiles_url").presence || ENV["TILES_URL"].presence
    @theme        = Setting.get("tiles_theme").presence || ENV.fetch("TILES_THEME", "light")
    @regions_dir  = ENV.fetch("REGIONS_DIR") do
      candidates = [Rails.root.join("regions"), Rails.root.join("..", "regions")]
      candidates.find { |p| File.directory?(p) } || candidates.first
    end

    @region = RegionContext.current(regions_dir: @regions_dir)
    @active_regions = @region.names
    @default_lat  = @region.lat
    @default_lon  = @region.lon
    @default_zoom = @region.zoom

    @degraded = Service.where(enabled: true).where(status: DEGRADED_STATUSES).pluck(:name)

    @services = Service.order(:profile, :name)
    @regions  = safe_load_regions(@regions_dir)
    @region_selection = @active_regions
  end

  private

  def safe_load_regions(dir)
    catalog = RegionCatalog.load_dir(dir)
    catalog.respond_to?(:all) ? catalog.all : []
  rescue Errno::ENOENT
    []
  end
end
