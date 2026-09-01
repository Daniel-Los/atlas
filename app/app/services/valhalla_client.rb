class ValhallaClient < UpstreamService
  def self.default
    new(base_url: ENV.fetch("VALHALLA_URL", "http://localhost:8004"), timeout: 15)
  end

  MODES = %w[auto bicycle pedestrian].freeze

  def route(from:, to:, mode: "auto", options: {})
    raise ArgumentError, "invalid mode #{mode}" unless MODES.include?(mode)
    body = {
      locations: [
        { lat: from[:lat], lon: from[:lon] },
        { lat: to[:lat],   lon: to[:lon] }
      ],
      costing: mode,
      directions_options: { units: "kilometers" }
    }

    # Valhalla cost-model knobs for driving. Value 0.0 = avoid as much as
    # possible; 1.0 = prefer. Unset = engine default.
    if mode == "auto"
      costing_options = {}
      costing_options[:use_tolls]    = 0.0 if options[:avoid_tolls]
      costing_options[:use_highways] = 0.0 if options[:avoid_highways]
      costing_options[:use_ferry]    = 0.0 if options[:avoid_ferries]
      body[:costing_options] = { auto: costing_options } if costing_options.any?
    end

    response = conn.post("/route") do |req|
      req.headers["Content-Type"] = "application/json"
      req.body = body.to_json
    end
    raise BadResponse, "#{response.status} from valhalla" unless response.success?
    response.body
  rescue Faraday::ConnectionFailed, Faraday::TimeoutError => e
    raise Unavailable, "Valhalla unreachable: #{e.message}"
  end
end
