class BatchReverseGeocoder
  MAX_COORDS    = 500
  GRID_DECIMALS = 4    # ~11 m precision; absorbs typical phone GPS noise
  CACHE_TTL     = 30.days
  CACHE_VERSION = "v1"

  Result = Struct.new(:results, :cache_hits, :cache_misses, :upstream_errors, keyword_init: true)

  def initialize(orchestrator: ReverseOrchestrator.new)
    @orchestrator = orchestrator
  end

  def call(coords:, lang: nil)
    raise ArgumentError, "coords must be an Array" unless coords.is_a?(Array)
    raise ArgumentError, "too many coords (max #{MAX_COORDS})" if coords.length > MAX_COORDS

    hits = misses = errors = 0
    results = coords.map do |entry|
      raw_lat = entry["lat"] || entry[:lat]
      raw_lon = entry["lon"] || entry[:lon]
      id      = entry["id"]  || entry[:id]

      lat = Float(raw_lat)
      lon = Float(raw_lon)
      key = cache_key(lat: lat, lon: lon, lang: lang)

      payload = Rails.cache.fetch(key, expires_in: CACHE_TTL) do
        miss = @orchestrator.lookup(lat: lat, lon: lon, lang: lang)
        misses += 1
        errors += 1 unless miss.upstream_status == "ok"
        { feature: miss.feature, admin: miss.admin, upstream_status: miss.upstream_status }
      end
      hits += 1 if payload && !misses.positive?

      {
        id:    id,
        coord: { lat: lat, lon: lon },
        here:  payload[:feature],
        admin: payload[:admin]
      }
    rescue ArgumentError, TypeError => e
      errors += 1
      { id: id, coord: { lat: raw_lat, lon: raw_lon }, error: e.message }
    end

    Result.new(
      results:         results,
      cache_hits:      hits,
      cache_misses:    misses,
      upstream_errors: errors
    )
  end

  private

  def cache_key(lat:, lon:, lang:)
    snapped_lat = lat.round(GRID_DECIMALS)
    snapped_lon = lon.round(GRID_DECIMALS)
    "rg:#{CACHE_VERSION}:#{snapped_lat}:#{snapped_lon}:#{lang || 'default'}"
  end
end
