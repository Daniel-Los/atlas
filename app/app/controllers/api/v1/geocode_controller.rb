module Api
  module V1
    class GeocodeController < BaseController
      def index
        query = params[:q].to_s.strip
        lat   = parse_float(params[:lat])
        lon   = parse_float(params[:lon])

        if query.empty? && (lat.nil? || lon.nil?)
          raise ActionController::ParameterMissing, "supply either `q=` (forward) or `lat=&lon=` (reverse)"
        end

        if query.empty?
          render json: reverse(lat: lat, lon: lon)
        else
          render json: forward(query: query, lat: lat, lon: lon)
        end
      end

      private

      def forward(query:, lat:, lon:)
        limit = clamp_int(params[:limit], default: 8, min: 1, max: 25)
        lang  = params[:lang].presence
        result = SearchOrchestrator.new.autocomplete(query: query, limit: limit, lang: lang, lat: lat, lon: lon)
        {
          data: result.features,
          meta: meta.merge(mode: "forward", upstream: result.upstream_status, count: result.features.length)
        }
      end

      def reverse(lat:, lon:)
        lang  = params[:lang].presence
        result = ReverseOrchestrator.new.lookup(lat: lat, lon: lon, lang: lang)
        {
          data: { here: result.feature, admin: result.admin },
          meta: meta.merge(mode: "reverse", upstream: result.upstream_status)
        }
      end
    end
  end
end
