class OtpClient < UpstreamService
  def self.default
    new(base_url: ENV.fetch("OTP_URL", "http://localhost:8080"), timeout: 15)
  end

  DEFAULT_MODES = "TRANSIT,WALK".freeze

  def plan(from:, to:, time: Time.now, modes: DEFAULT_MODES, num: 3, arrive_by: false)
    params = {
      fromPlace:      "#{from[:lat]},#{from[:lon]}",
      toPlace:        "#{to[:lat]},#{to[:lon]}",
      mode:           modes,
      date:           time.strftime("%Y-%m-%d"),
      time:           time.strftime("%H:%M:%S"),
      numItineraries: num,
      arriveBy:       arrive_by
    }
    response = conn.get("/otp/routers/default/plan", params)
    raise BadResponse, "#{response.status} from OTP" unless response.success?
    if response.body.is_a?(Hash) && response.body["error"]
      raise BadResponse, "OTP plan error: #{response.body["error"]["msg"] || response.body["error"]}"
    end
    response.body
  rescue Faraday::ConnectionFailed, Faraday::TimeoutError => e
    raise Unavailable, "OTP unreachable: #{e.message}"
  end
end
