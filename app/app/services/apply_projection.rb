class ApplyProjection
  Summary = Struct.new(:total_disk_gb, :first_boot_hours, :lines, keyword_init: true)
  Line    = Struct.new(:name, :disk_gb, :hours, keyword_init: true) do
    def to_h = { name: name, disk_gb: disk_gb, hours: hours }
  end

  CITY_DISK = {
    "photon"      => 8.0,
    "placeholder" => 4.0,
    "libpostal"   => 0.0,
    "valhalla"    => 1.0,
    "overpass"    => 4.0,
    "otp"         => 1.0
  }.freeze

  COUNTRY_DISK = {
    "photon" => 8.0, "placeholder" => 4.0, "libpostal" => 0.0,
    "valhalla" => 15.0, "overpass" => 45.0, "otp" => 5.0
  }.freeze

  CONTINENT_DISK = {
    "photon" => 30.0, "placeholder" => 4.0, "libpostal" => 0.0,
    "valhalla" => 115.0, "overpass" => 280.0, "otp" => 30.0
  }.freeze

  PLANET_DISK = {
    "photon" => 110.0, "placeholder" => 4.0, "libpostal" => 0.0,
    "valhalla" => 250.0, "overpass" => 700.0, "otp" => 50.0
  }.freeze

  HOURS = {
    "photon" => 2.0, "placeholder" => 1.5, "libpostal" => 0.05,
    "valhalla" => 1.5, "overpass" => 6.0, "otp" => 1.0
  }.freeze

  def initialize(regions:, services:)
    @regions  = regions
    @services = services
  end

  def summary
    table = scaling_table
    lines = @services.map do |svc|
      disk = table.fetch(svc, 0.0)
      Line.new(name: svc, disk_gb: disk, hours: HOURS.fetch(svc, 0.0))
    end
    Summary.new(
      total_disk_gb:    lines.sum(&:disk_gb).round(1),
      first_boot_hours: lines.map(&:hours).max.to_f.round(1),
      lines:            lines.map(&:to_h)
    )
  end

  private

  def scaling_table
    return CITY_DISK     if @regions.empty?
    case classify(@regions.first)
    when :city     then CITY_DISK
    when :country  then COUNTRY_DISK
    when :continent then CONTINENT_DISK
    when :planet   then PLANET_DISK
    end
  end

  def classify(region)
    return :planet    if region.name == "planet"
    return :continent if region.name == "europe"
    return :country   if %w[germany france italy].include?(region.name) || region.country_code && region.pbf_urls.first&.include?("geofabrik")
    :city
  end
end
