module Api
  module V1
    class WhatsHereController < BaseController
      def index
        lat = require_float(:lat)
        lon = require_float(:lon)
        radius = clamp_int(params[:radius], default: 200, min: 10, max: 2000)

        reverse = ReverseOrchestrator.new.lookup(lat: lat, lon: lon, lang: params[:lang].presence)
        nearby_raw = OverpassClient.default.around(lat: lat, lon: lon, radius: radius)

        render json: {
          data: {
            here:   reverse.feature,
            admin:  reverse.admin,
            nearby: poi_features(nearby_raw)
          },
          meta: meta.merge(radius: radius, upstream: reverse.upstream_status)
        }
      end

      private

      def poi_features(geojson)
        elements = geojson.is_a?(Hash) ? geojson["elements"].to_a : []
        elements.map do |el|
          coords = el["center"] || { "lat" => el["lat"], "lon" => el["lon"] }
          {
            id: "#{el['type']}/#{el['id']}",
            coords: { lon: coords["lon"], lat: coords["lat"] },
            tags: el["tags"] || {}
          }
        end
      end
    end
  end
end
