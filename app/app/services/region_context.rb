class RegionContext
  WORLD_LAT  = 51.1657
  WORLD_LON  = 10.4515
  WORLD_ZOOM = 2

  attr_reader :names, :lat, :lon, :zoom

  def initialize(names:, lat:, lon:, zoom:)
    @names = names
    @lat   = lat
    @lon   = lon
    @zoom  = zoom
  end

  def self.current(regions_dir:)
    names = RegionSelection.where(active: true).order(:position).pluck(:region_name)
    if names.empty?
      return new(names: [], lat: WORLD_LAT, lon: WORLD_LON, zoom: WORLD_ZOOM)
    end

    catalog = RegionCatalog.load_dir(regions_dir)
    first   = catalog.find(names.first)
    view    = first.default_view
    new(
      names: names,
      lat:   view[:lat]  || WORLD_LAT,
      lon:   view[:lon]  || WORLD_LON,
      zoom:  view[:zoom] || WORLD_ZOOM
    )
  rescue RegionCatalog::Region::NotFound
    new(names: names, lat: WORLD_LAT, lon: WORLD_LON, zoom: WORLD_ZOOM)
  end

  def empty?
    names.empty?
  end

  def label
    return nil if empty?
    names.size == 1 ? names.first.titleize : "#{names.size} regions"
  end
end
