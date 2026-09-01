class PhotonClient < UpstreamService
  def self.default
    new(base_url: ENV.fetch("PHOTON_URL", "http://localhost:8001"))
  end

  # Photon /api accepts:
  #   q        — free text
  #   limit    — max results
  #   lang     — language
  #   lat/lon  — biases results toward a location
  #   bbox     — west,south,east,north — hard restricts results
  #   osm_tag  — repeatable "key:value" filter (e.g. amenity:cafe, tourism:hotel)
  def search(query:, limit: 10, lang: nil, lat: nil, lon: nil, bbox: nil, osm_tags: nil)
    pairs = [["q", query], ["limit", limit]]
    pairs << ["lang", lang] if lang
    pairs << ["lat", lat]   if lat
    pairs << ["lon", lon]   if lon
    pairs << ["bbox", bbox.join(",")] if bbox.is_a?(Array) && bbox.size == 4
    Array(osm_tags).each { |t| pairs << ["osm_tag", t] }
    # Photon needs `osm_tag=...&osm_tag=...` repeated, not Rails `osm_tag[]=`.
    query_string = pairs.map { |k, v| "#{k}=#{CGI.escape(v.to_s)}" }.join("&")

    response = conn.get("/api?#{query_string}")
    raise BadResponse, "#{response.status} from #{@base_url}/api" unless response.success?
    response.body
  rescue Faraday::ConnectionFailed, Faraday::TimeoutError => e
    raise Unavailable, "#{self.class.name} at #{@base_url}: #{e.message}"
  end

  def reverse(lat:, lon:, radius: nil, lang: nil)
    params = { lat: lat, lon: lon }
    params[:radius] = radius if radius
    params[:lang] = lang if lang
    get("/reverse", params)
  end
end
