class ReverseOrchestrator
  Result = Struct.new(:feature, :admin, :upstream_status, keyword_init: true)

  def initialize(photon:      PhotonClient.default,
                 placeholder: PlaceholderClient.default)
    @photon      = photon
    @placeholder = placeholder
  end

  # Sequential pipeline:
  #   1. photon.reverse(lat, lon)                  → nearest labeled feature + Photon's own admin tags
  #   2. placeholder.admin_for(feature.name)       → richer admin chain when Photon's tags are thin
  def lookup(lat:, lon:, lang: nil)
    body = @photon.reverse(lat: lat, lon: lon, lang: lang)
    feature = normalize(body)

    admin = feature ? feature[:admin] : {}
    if feature && (admin[:city].blank? || admin[:country].blank?)
      placeholder_admin = @placeholder.admin_for(text: feature[:name].to_s, lang: lang)
      admin = placeholder_admin.merge(admin) if placeholder_admin
    end

    Result.new(feature: feature, admin: admin, upstream_status: "ok")
  rescue UpstreamService::Unavailable => e
    Rails.logger.warn("photon unavailable: #{e.message}")
    Result.new(feature: nil, admin: {}, upstream_status: "unavailable")
  rescue UpstreamService::BadResponse => e
    Rails.logger.warn("photon bad response: #{e.message}")
    Result.new(feature: nil, admin: {}, upstream_status: "error")
  end

  private

  def normalize(geojson)
    feature = geojson.is_a?(Hash) ? geojson["features"]&.first : nil
    return nil unless feature

    props  = feature["properties"] || {}
    coords = (feature["geometry"] || {})["coordinates"] || []

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
