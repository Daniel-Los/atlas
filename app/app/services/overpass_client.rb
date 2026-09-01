class OverpassClient < UpstreamService
  def self.default
    new(base_url: ENV.fetch("OVERPASS_URL", "http://localhost:8005"), timeout: 20)
  end

  def around(lat:, lon:, radius: 200, filters: ["amenity", "shop", "tourism", "leisure"])
    selectors = filters.map { |f| "nwr[#{f}](around:#{radius},#{lat},#{lon});" }.join
    run_query("[out:json][timeout:15];(#{selectors});out center tags 50;")
  end

  # bbox: [south, west, north, east]
  # filters: array of OSM tag selectors like "amenity=cafe" or "amenity" (any value).
  def bbox(bbox:, filters:, limit: 200)
    box = bbox.map(&:to_f).join(",")
    selectors = filters.map { |f| "nwr[#{f}](#{box});" }.join
    run_query("[out:json][timeout:15];(#{selectors});out center tags #{limit.to_i};")
  end

  private

  def run_query(query)
    response = conn.post("/api/interpreter") do |req|
      req.headers["Content-Type"] = "text/plain"
      req.body = query
    end
    raise BadResponse, "#{response.status} from overpass" unless response.success?
    response.body
  rescue Faraday::ConnectionFailed, Faraday::TimeoutError => e
    raise Unavailable, "Overpass unreachable: #{e.message}"
  end
end
