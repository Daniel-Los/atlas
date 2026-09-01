class LibpostalClient < UpstreamService
  def self.default
    new(base_url: ENV.fetch("LIBPOSTAL_URL", "http://localhost:8003"), timeout: 3)
  end

  def parse(address)
    body = get("/parser", address: address)
    body.is_a?(Array) ? body : []
  end

  def to_tokens(parsed)
    parsed.each_with_object({}) do |entry, h|
      label = entry.is_a?(Hash) ? entry["label"] : nil
      value = entry.is_a?(Hash) ? entry["value"] : nil
      h[label] = value if label && value
    end
  end

  def normalize(address)
    parsed = parse(address)
    return { query: address, tokens: {} } if parsed.empty?

    tokens = to_tokens(parsed)
    canonical = %w[house house_number road suburb city state postcode country]
                  .map { |k| tokens[k] }.compact.join(", ")
    { query: canonical.presence || address, tokens: tokens }
  rescue UpstreamService::Error
    { query: address, tokens: {} }
  end
end
