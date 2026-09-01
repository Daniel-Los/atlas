class DatasetRegistry
  class Entry
    KINDS = %w[incremental full_refresh image_only manual_only].freeze
    CONTINUOUS = "@continuous".freeze

    attr_reader :name, :update_kind, :disk_impact, :default_schedule, :notes

    def initialize(name, attrs)
      @name             = name
      @update_kind      = attrs.fetch("update_kind")
      @disk_impact      = attrs.fetch("disk_impact", {})
      @default_schedule = attrs["default_schedule"]
      @notes            = attrs["notes"]
      raise ArgumentError, "unknown update_kind #{@update_kind.inspect} for #{name}" unless KINDS.include?(@update_kind)
    end

    def continuous?         = default_schedule == CONTINUOUS
    def image_only?         = update_kind == "image_only"
    def full_refresh?       = update_kind == "full_refresh"
    def incremental?        = update_kind == "incremental"
    def manual_only?        = update_kind == "manual_only"

    def disk_impact_summary
      kind = update_kind
      di   = disk_impact
      case kind
      when "image_only"
        "Image pull only (~#{di['transient_mb'] || di['transient_gb'] && di['transient_gb'] * 1024} MB transient)"
      when "incremental"
        per_day = di["growth_mb_per_day"]
        per_day ? "Incremental — ~#{per_day} MB/day growth" : "Incremental — negligible"
      when "full_refresh"
        t = di["transient_gb"]; p = di["persistent_gb"]
        "Full refresh — ~#{t} GB transient, replaces ~#{p} GB on disk"
      when "manual_only"
        t = di["transient_gb"]
        t ? "Manual only — ~#{t} GB transient" : "Manual only"
      end
    end
  end

  DEFAULT_PATH = Rails.root.join("config", "datasets.yml")

  def self.default = @default ||= load_file(DEFAULT_PATH)

  def self.reload!
    @default = nil
    default
  end

  def self.load_file(path)
    raw = YAML.safe_load_file(path, permitted_classes: [], aliases: false)
    new(raw || {})
  end

  def initialize(raw)
    @entries = raw.to_h { |name, attrs| [name, Entry.new(name, attrs)] }
  end

  def [](name) = @entries[name.to_s]
  def fetch(name) = @entries.fetch(name.to_s)
  def names       = @entries.keys
  def known?(name) = @entries.key?(name.to_s)
end
