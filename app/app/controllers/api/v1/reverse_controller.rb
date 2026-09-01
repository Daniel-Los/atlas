module Api
  module V1
    class ReverseController < BaseController
      def show
        lat  = require_float(:lat)
        lon  = require_float(:lon)
        lang = params[:lang].presence

        result = ReverseOrchestrator.new.lookup(lat: lat, lon: lon, lang: lang)

        render json: {
          data: { here: result.feature, admin: result.admin },
          meta: meta.merge(upstream: result.upstream_status)
        }
      end

      def batch
        coords = params.require(:coords)
        raise ActionController::ParameterMissing.new(:coords) unless coords.is_a?(Array)
        lang = params[:lang].presence

        result = BatchReverseGeocoder.new.call(coords: coords, lang: lang)

        render json: {
          data: result.results,
          meta: meta.merge(
            count:           result.results.length,
            cache_hits:      result.cache_hits,
            cache_misses:    result.cache_misses,
            upstream_errors: result.upstream_errors,
            grid_precision:  BatchReverseGeocoder::GRID_DECIMALS,
            max_coords:      BatchReverseGeocoder::MAX_COORDS
          )
        }
      end
    end
  end
end
