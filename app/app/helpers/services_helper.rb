module ServicesHelper
  SERVICE_DESCRIPTIONS = {
    "photon"      => "Forward + reverse geocoding. Turns search text into coordinates and back. Uses OpenStreetMap with a country-scoped Photon index.",
    "placeholder" => "Coarse geocoder for administrative places (cities, regions, neighbourhoods). Used as a fallback and disambiguator alongside Photon. Needs Who's On First data.",
    "libpostal"   => "Statistical address parser and normalizer. Splits free-text addresses into components (street, city, postcode) and expands abbreviations across many locales.",
    "valhalla"    => "Routing engine. Computes turn-by-turn directions for driving, cycling, and walking. Builds graph tiles from the active OSM PBF.",
    "overpass"    => "POI and tag-level queries against OpenStreetMap. Powers “what's here” lookups and find-by-amenity searches.",
    "otp"         => "OpenTripPlanner. Multimodal public-transit routing combining GTFS feeds with the OSM road graph.",
    "whosonfirst" => "Pelias' gazetteer of administrative places. One-time download (~6 GB) consumed by Placeholder."
  }.freeze

  def service_description(name)
    SERVICE_DESCRIPTIONS[name] || "Backend service: #{name}."
  end
end
