module Api
  module V1
    class PoisController < BaseController
      def index
        bbox = parse_bbox(params.require(:bbox))
        types = Array(params[:types]).flat_map { |t| t.to_s.split(",") }.map(&:strip).reject(&:empty?)
        types = catalog.pinned.first(2).map(&:id) if types.empty?
        query = params[:q].to_s.strip

        selectors = catalog.selectors_for(types)
        if selectors.empty?
          render json: { error: { code: "BAD_REQUEST", message: "no recognised types" } }, status: :unprocessable_entity and return
        end

        features = if query.present?
          search_within_categories(query: query, bbox: bbox, selectors: selectors, types: types)
        else
          raw = OverpassClient.default.bbox(bbox: bbox, filters: selectors, limit: 300)
          serialize_features(raw, types)
        end

        render json: {
          data: { features: features },
          meta: meta.merge(types: types, bbox: bbox, q: query.presence)
        }
      end

      def categories
        # Inline each icon's SVG so the panel renders instantly without per-icon
        # HTTP fetches.
        sections = catalog.sections.map do |s|
          {
            id:       s.id,
            label:    s.label,
            icon:     s.icon,
            icon_svg: render_icon(s.icon),
            items:    s.items.map do |i|
              {
                id:       i.id,
                label:    i.label,
                icon:     i.icon,
                icon_svg: render_icon(i.icon),
                pinned:   i.pinned
              }
            end
          }
        end
        render json: { data: { sections: sections } }, status: :ok
      end

      private

      # Free-text name/address search via Photon, scoped by bbox + osm_tag
      # filter mapped from the user-selected categories. Photon handles fuzzy
      # name matching and address parsing far better than an overpass regex.
      def search_within_categories(query:, bbox:, selectors:, types:)
        osm_tags = selectors.map { |sel| sel.gsub("=", ":") }
        # Photon expects bbox as west,south,east,north — our bbox is south,west,north,east.
        photon_bbox = [bbox[1], bbox[0], bbox[3], bbox[2]]
        raw = PhotonClient.default.search(query: query, limit: 50, bbox: photon_bbox, osm_tags: osm_tags)
        Array(raw["features"]).map do |feat|
          props = feat["properties"] || {}
          coords = feat.dig("geometry", "coordinates") || []
          tags = osm_tags_from_properties(props)
          {
            id:       "#{props['osm_type']}/#{props['osm_id']}",
            coords:   { lon: coords[0], lat: coords[1] },
            name:     props["name"],
            category: derive_category_from_tags(tags, types),
            tags:     tags
          }
        end
      end

      # Photon returns a flat properties hash; reconstruct the OSM tag layout
      # the rest of the UI expects.
      def osm_tags_from_properties(p)
        tags = {}
        tags["name"]              = p["name"]    if p["name"]
        tags["addr:street"]       = p["street"]  if p["street"]
        tags["addr:housenumber"]  = p["housenumber"] if p["housenumber"]
        tags["addr:postcode"]     = p["postcode"] if p["postcode"]
        tags["addr:city"]         = p["city"]     if p["city"]
        tags["addr:country"]      = p["country"]  if p["country"]
        # Photon exposes the OSM key it indexed under in `osm_key` / `osm_value`.
        tags[p["osm_key"]] = p["osm_value"] if p["osm_key"] && p["osm_value"]
        tags
      end

      def derive_category_from_tags(tags, types)
        types.each do |t|
          item = catalog.find(t)
          next unless item
          key, value = item.selector.split("=", 2)
          return t if tags[key] == value
        end
        types.first || "other"
      end

      def render_icon(name)
        return nil if name.blank?
        path = Rails.root.join("app/assets/svg/icons/lucide/outline/#{name}.svg")
        File.read(path) if File.exist?(path)
      end

      def catalog
        PoiCatalog.load
      end

      def parse_bbox(raw)
        parts = raw.to_s.split(",").map(&:strip)
        raise ArgumentError, "bbox must be south,west,north,east" unless parts.length == 4
        parts.map { |p| Float(p) }
      end

      def serialize_features(geojson, requested_types)
        elements = geojson.is_a?(Hash) ? geojson["elements"].to_a : []
        elements.map do |el|
          coords = el["center"] || { "lat" => el["lat"], "lon" => el["lon"] }
          tags = el["tags"] || {}
          {
            id:        "#{el['type']}/#{el['id']}",
            coords:    { lon: coords["lon"], lat: coords["lat"] },
            name:      tags["name"] || tags["brand"],
            category:  derive_category(tags, requested_types),
            tags:      tags
          }
        end
      end

      # Map an OSM element back to one of the requested category ids by checking
      # the selector predicate (key=value) against the tags hash.
      def derive_category(tags, requested_types)
        requested_types.each do |type|
          item = catalog.find(type)
          next unless item
          key, value = item.selector.split("=", 2)
          return type if tags[key] == value
        end
        "other"
      end
    end
  end
end
