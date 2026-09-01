class UpstreamService
  class Error < StandardError; end
  class Unavailable < Error; end
  class BadResponse < Error; end

  def initialize(base_url:, timeout: 5)
    @base_url = base_url
    @timeout = timeout
  end

  private

  def conn
    @conn ||= Faraday.new(url: @base_url) do |f|
      f.request :url_encoded
      f.options.timeout = @timeout
      f.options.open_timeout = 2
      f.response :json, content_type: /\bjson$/
    end
  end

  def get(path, params = {})
    response = conn.get(path, params)
    raise BadResponse, "#{response.status} from #{@base_url}#{path}" unless response.success?
    response.body
  rescue Faraday::ConnectionFailed, Faraday::TimeoutError => e
    raise Unavailable, "#{self.class.name} at #{@base_url}: #{e.message}"
  end
end
