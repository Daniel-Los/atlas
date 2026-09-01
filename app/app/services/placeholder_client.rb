class PlaceholderClient < UpstreamService
  def self.default
    new(base_url: ENV.fetch("PLACEHOLDER_URL", "http://localhost:8002"), timeout: 4)
  end

  def search(text:, lang: nil)
    params = { text: text }
    params[:lang] = lang if lang
    body = get("/parser/search", params)
    body.is_a?(Array) ? body : []
  end

  def find_by_id(ids:, lang: nil)
    params = { ids: Array(ids).join(",") }
    params[:lang] = lang if lang
    body = get("/parser/findbyid", params)
    body.is_a?(Array) ? body : []
  end

  def admin_for(text:, lang: nil)
    hits = search(text: text, lang: lang)
    top = hits.first
    return nil unless top

    lineage = top["lineage"].is_a?(Array) ? top["lineage"].first : nil
    return nil unless lineage

    {
      country:  lineage.dig("country", "name"),
      state:    lineage.dig("region", "name"),
      county:   lineage.dig("county", "name"),
      city:     lineage.dig("locality", "name") || lineage.dig("localadmin", "name"),
      borough:  lineage.dig("borough", "name"),
      neighborhood: lineage.dig("neighbourhood", "name")
    }.compact
  rescue UpstreamService::Error
    nil
  end
end
