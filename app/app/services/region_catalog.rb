class RegionCatalog
  class Region < Struct.new(:name, :label, :country_code, :pbf_urls, :default_view, keyword_init: true)
    class NotFound < StandardError; end

    def multi?
      pbf_urls.length > 1
    end
  end

  attr_reader :regions

  def initialize(regions)
    @regions = regions.index_by(&:name)
  end

  def self.load_dir(path)
    files = Dir.glob(File.join(path.to_s, "*.env"))
    regions = files.map do |file|
      name = File.basename(file, ".env")
      env  = EnvParser.parse(File.read(file))
      Region.new(
        name:         name,
        label:        env["REGION_LABEL"] || name,
        country_code: env["COUNTRY_CODE"],
        pbf_urls:     extract_pbf_urls(env),
        default_view: extract_view(env)
      )
    end
    new(regions)
  end

  def find(name)
    regions.fetch(name) { raise Region::NotFound, "region '#{name}' not in catalog" }
  end

  def names
    regions.keys
  end

  def all
    regions.values
  end

  def self.extract_pbf_urls(env)
    if env["PBF_URLS"].to_s.strip != ""
      env["PBF_URLS"].split(/\s+/)
    elsif env["PBF_URL"]
      [env["PBF_URL"]]
    else
      []
    end
  end

  def self.extract_view(env)
    { lat:  env["DEFAULT_LAT"]&.to_f,
      lon:  env["DEFAULT_LON"]&.to_f,
      zoom: env["DEFAULT_ZOOM"]&.to_i }
  end

  module EnvParser
    KEY_VALUE = /\A([A-Z_][A-Z0-9_]*)=(.*)\z/

    def self.parse(content)
      content.each_line.each_with_object({}) do |line, acc|
        line = line.strip
        next if line.empty? || line.start_with?("#")
        next unless (match = line.match(KEY_VALUE))

        key   = match[1]
        value = unquote(match[2])
        acc[key] = value
      end
    end

    def self.unquote(value)
      if value.start_with?('"') && value.end_with?('"')
        value[1..-2]
      else
        value
      end
    end
  end
end
