module Admin
  class TilesController < BaseController
    LOCAL_URL = "/tiles/basemap.pmtiles".freeze
    THEMES    = %w[light dark grayscale white black].freeze

    def show
      render json: { data: state }
    end

    # Trigger a download into data/tiles/basemap.pmtiles.
    def download
      url = params.require(:url).to_s
      raise ArgumentError, "url must be http(s)" unless url.match?(%r{\Ahttps?://})
      ControlPlaneClient.default.download_tiles!(url)
      render json: { ok: true, downloading_from: url }, status: :accepted
    rescue ArgumentError => e
      render json: { error: { code: "BAD_REQUEST", message: e.message } }, status: :unprocessable_entity
    rescue ControlPlaneClient::Unavailable, ControlPlaneClient::BadResponse => e
      render json: { error: { code: "SIDECAR_ERROR", message: e.message } }, status: :bad_gateway
    end

    # Update the runtime TILES_URL override. Pass `url=...` or `source=local|env`.
    def update
      source = params[:source].to_s
      case source
      when "local"
        Setting.set("tiles_url", LOCAL_URL)
      when "env"
        Setting.unset("tiles_url")
      when "url"
        url = params.require(:url).to_s
        raise ArgumentError, "url required" if url.empty?
        Setting.set("tiles_url", url)
      else
        raise ArgumentError, "source must be local, env, or url"
      end
      render json: { ok: true, effective: effective_tiles_url }
    rescue ArgumentError => e
      render json: { error: { code: "BAD_REQUEST", message: e.message } }, status: :unprocessable_entity
    end

    def update_theme
      theme = params.require(:theme).to_s
      raise ArgumentError, "theme must be one of: #{THEMES.join(', ')}" unless THEMES.include?(theme)
      Setting.set("tiles_theme", theme)
      render json: { ok: true, theme: theme }
    rescue ArgumentError => e
      render json: { error: { code: "BAD_REQUEST", message: e.message } }, status: :unprocessable_entity
    end

    private

    def state
      sidecar = sidecar_status
      {
        effective:       effective_tiles_url,
        override:        Setting.get("tiles_url"),
        env:             ENV["TILES_URL"].presence,
        theme:           effective_tiles_theme,
        local:           sidecar
      }
    end

    def sidecar_status
      ControlPlaneClient.default.tiles_status
    rescue ControlPlaneClient::Unavailable, ControlPlaneClient::BadResponse
      { "exists" => false }
    end

    def effective_tiles_url
      Setting.get("tiles_url") || ENV["TILES_URL"].presence
    end

    def effective_tiles_theme
      Setting.get("tiles_theme").presence || ENV.fetch("TILES_THEME", "light")
    end
  end
end
