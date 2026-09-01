class SearchOrchestrator
  Result = Struct.new(:features, :upstream_status, keyword_init: true)

  def initialize(libpostal: LibpostalClient.default,
                 photon:    PhotonClient.default,
                 placeholder: PlaceholderClient.default)
    @libpostal   = libpostal
    @photon      = photon
    @placeholder = placeholder
  end

  # Sequential pipeline:
  #   1. libpostal.parse → tokens + canonical query  (best-effort, silent on failure)
  #   2. photon.search(query)                        (primary upstream)
  #   3. for each feature → placeholder admin lookup (enrichment; keeps Photon's tags if Placeholder is silent)
  def autocomplete(query:, limit: 8, lang: nil, lat: nil, lon: nil, bbox: nil)
    normalized = @libpostal.normalize(query)
    photon_query = normalized.fetch(:query)

    body = @photon.search(query: photon_query, limit: limit, lang: lang, lat: lat, lon: lon, bbox: bbox)
    features = normalize_photon(body)

    enriched = features.map { |feature| enrich_with_placeholder(feature, lang: lang) }

    Result.new(features: enriched, upstream_status: "ok")
  rescue UpstreamService::Unavailable => e
    Rails.logger.warn("photon unavailable: #{e.message}")
    Result.new(features: [], upstream_status: "unavailable")
  rescue UpstreamService::BadResponse => e
    Rails.logger.warn("photon bad response: #{e.message}")
    Result.new(features: [], upstream_status: "error")
  end

  private

  def normalize_photon(geojson)
    features = geojson.is_a?(Hash) ? geojson["features"].to_a : []
    features.map do |f|
      props = f["properties"] || {}
      geom  = f["geometry"] || {}
      coords = geom["coordinates"] || []
      {
        id:    [props["osm_type"], props["osm_id"]].compact.join(":"),
        name:  props["name"],
        label: [props["name"], props["city"], props["state"], props["country"]].compact.uniq.join(", "),
        type:  props["osm_value"] || props["osm_key"],
        coords: { lon: coords[0], lat: coords[1] },
        admin: {
          country:  props["country"],
          state:    props["state"],
          county:   props["county"],
          city:     props["city"],
          postcode: props["postcode"]
        }.compact
      }
    end
  end

  def enrich_with_placeholder(feature, lang:)
    return feature if feature[:admin][:country] && feature[:admin][:city]

    placeholder_admin = @placeholder.admin_for(text: feature[:name].to_s, lang: lang)
    return feature unless placeholder_admin

    merged_admin = placeholder_admin.merge(feature[:admin]) # Photon wins where present
    feature.merge(admin: merged_admin)
  end
end
