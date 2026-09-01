class StaticMapsController < ApplicationController
  layout "static"

  def show
    @tiles_url = Setting.get("tiles_url").presence || ENV["TILES_URL"].presence
    @theme     = (params[:theme].presence || Setting.get("tiles_theme").presence || ENV.fetch("TILES_THEME", "light")).to_s

    @lat    = float_or(params[:lat],    51.1657)
    @lon    = float_or(params[:lon],    10.4515)
    @zoom   = float_or(params[:zoom],   5)
    @width  = clamp_int(params[:width],  64, 4096, 800)
    @height = clamp_int(params[:height], 64, 4096, 600)

    @route    = params[:route].to_s
    @title    = params[:title].to_s
    @subtitle = params[:subtitle].to_s
    @brand    = params[:brand].presence&.to_s || "Dawarich Atlas"
    @fit      = params[:fit].to_s == "1"
  end

  private

  def float_or(value, fallback)
    Float(value)
  rescue ArgumentError, TypeError
    fallback
  end

  def clamp_int(value, min, max, fallback)
    n = Integer(value)
    n.clamp(min, max)
  rescue ArgumentError, TypeError
    fallback
  end
end
