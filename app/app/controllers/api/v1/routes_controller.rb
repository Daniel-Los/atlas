module Api
  module V1
    class RoutesController < BaseController
      def show
        from = parse_latlon(params.require(:from), key: :from)
        to   = parse_latlon(params.require(:to),   key: :to)
        mode = params[:mode].presence || "auto"
        options = {
          avoid_tolls:    truthy?(params[:avoid_tolls]),
          avoid_highways: truthy?(params[:avoid_highways]),
          avoid_ferries:  truthy?(params[:avoid_ferries])
        }

        result = ValhallaClient.default.route(from: from, to: to, mode: mode, options: options)

        render json: {
          data: {
            summary: (result.dig("trip", "summary") || {}),
            legs:    (result.dig("trip", "legs") || []),
            shape_format: "valhalla_encoded_polyline6"
          },
          meta: meta.merge(mode: mode, options: options)
        }
      end

      private

      def truthy?(v)
        ActiveModel::Type::Boolean.new.cast(v) == true
      end

      def parse_latlon(raw, key:)
        lat_str, lon_str = raw.to_s.split(",", 2)
        raise ArgumentError, "#{key} must be 'lat,lon'" if lon_str.nil?
        { lat: Float(lat_str), lon: Float(lon_str) }
      rescue ArgumentError => e
        raise ArgumentError, "invalid #{key}: #{e.message}"
      end
    end
  end
end
