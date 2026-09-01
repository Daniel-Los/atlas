module Api
  module V1
    class TransitsController < BaseController
      def show
        from = parse_latlon(params.require(:from), key: :from)
        to   = parse_latlon(params.require(:to),   key: :to)
        time = parse_time(params[:time])
        modes = params[:modes].presence || OtpClient::DEFAULT_MODES
        num   = (params[:num] || 3).to_i.clamp(1, 6)

        result = OtpClient.default.plan(from: from, to: to, time: time, modes: modes, num: num)

        render json: {
          data: serialize_plan(result["plan"] || {}),
          meta: meta.merge(time: time.iso8601, modes: modes)
        }
      end

      private

      def parse_latlon(raw, key:)
        lat_str, lon_str = raw.to_s.split(",", 2)
        raise ArgumentError, "#{key} must be 'lat,lon'" if lon_str.nil?
        { lat: Float(lat_str), lon: Float(lon_str) }
      rescue ArgumentError => e
        raise ArgumentError, "invalid #{key}: #{e.message}"
      end

      def parse_time(raw)
        return Time.now if raw.blank?
        Time.parse(raw)
      rescue ArgumentError
        Time.now
      end

      def serialize_plan(plan)
        {
          from: plan["from"],
          to:   plan["to"],
          itineraries: Array(plan["itineraries"]).map do |it|
            {
              start_time:     it["startTime"],
              end_time:       it["endTime"],
              duration:       it["duration"],
              walk_distance:  it["walkDistance"],
              transfers:      it["transfers"],
              legs:           Array(it["legs"]).map { |l| serialize_leg(l) }
            }
          end
        }
      end

      def serialize_leg(leg)
        {
          mode:           leg["mode"],
          route_name:     leg["routeShortName"] || leg["route"],
          headsign:       leg["headsign"],
          agency_name:    leg["agencyName"],
          start_time:     leg["startTime"],
          end_time:       leg["endTime"],
          duration:       leg["duration"],
          distance:       leg["distance"],
          from:           { name: leg.dig("from", "name"), lat: leg.dig("from", "lat"), lon: leg.dig("from", "lon") },
          to:             { name: leg.dig("to", "name"),   lat: leg.dig("to", "lat"),   lon: leg.dig("to", "lon") },
          shape:          leg.dig("legGeometry", "points"),
          shape_format:   "google_polyline5"
        }
      end
    end
  end
end
