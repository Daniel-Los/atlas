module Api
  module V1
    class BaseController < ActionController::API
      rescue_from UpstreamService::Unavailable do |e|
        render json: error_payload("UPSTREAM_UNAVAILABLE", e.message), status: :service_unavailable
      end

      rescue_from UpstreamService::BadResponse do |e|
        render json: error_payload("UPSTREAM_ERROR", e.message), status: :bad_gateway
      end

      rescue_from ActionController::ParameterMissing do |e|
        render json: error_payload("VALIDATION_ERROR", e.message), status: :bad_request
      end

      rescue_from ArgumentError do |e|
        render json: error_payload("VALIDATION_ERROR", e.message), status: :unprocessable_entity
      end

      private

      def error_payload(code, message, details: nil)
        payload = { code: code, message: message }
        payload[:details] = details if details
        { error: payload }
      end

      def meta
        { timestamp: Time.current.iso8601 }
      end

      def clamp_int(raw, default:, min:, max:)
        return default if raw.blank?
        [[raw.to_i, min].max, max].min
      end

      def require_float(key)
        raw = params[key]
        raise ActionController::ParameterMissing.new(key) if raw.blank?
        Float(raw)
      rescue ArgumentError
        raise ArgumentError, "invalid #{key}: #{raw.inspect}"
      end

      def parse_float(raw)
        return nil if raw.blank?
        Float(raw)
      rescue ArgumentError
        raise ArgumentError, "invalid coordinate: #{raw.inspect}"
      end

      # Accepts "south,west,north,east" or "west,south,east,north" depending on
      # caller convention; here we use Photon-style west,south,east,north.
      def parse_bbox(raw)
        return nil if raw.blank?
        parts = raw.to_s.split(",").map(&:strip)
        raise ArgumentError, "bbox must be 4 comma-separated floats" unless parts.length == 4
        parts.map { |p| Float(p) }
      rescue ArgumentError
        raise ArgumentError, "invalid bbox: #{raw.inspect}"
      end
    end
  end
end
