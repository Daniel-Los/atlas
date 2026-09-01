module Api
  module V1
    class SearchController < BaseController
      def index
        query = params.require(:q).to_s.strip
        raise ActionController::ParameterMissing.new(:q) if query.empty?

        limit = clamp_int(params[:limit], default: 25, min: 1, max: 50)
        lang  = params[:lang].presence
        lat   = parse_float(params[:lat])
        lon   = parse_float(params[:lon])
        bbox  = parse_bbox(params[:bbox])

        result = SearchOrchestrator.new.autocomplete(query: query, limit: limit, lang: lang, lat: lat, lon: lon, bbox: bbox)

        render json: {
          data: result.features,
          meta: meta.merge(upstream: result.upstream_status, count: result.features.length)
        }
      end
    end
  end
end
