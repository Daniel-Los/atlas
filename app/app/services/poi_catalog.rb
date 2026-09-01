class PoiCatalog
  Item    = Struct.new(:id, :label, :selector, :icon, :pinned, :section, keyword_init: true)
  Section = Struct.new(:id, :label, :icon, :items, keyword_init: true)

  def self.load(path = Rails.root.join("config", "poi_categories.yml"))
    @instances ||= {}
    @instances[path] ||= new(YAML.safe_load_file(path))
  end

  def self.reload!
    @instances = {}
  end

  def initialize(yaml)
    @sections = (yaml["sections"] || []).map do |s|
      items = (s["items"] || []).map do |i|
        Item.new(
          id:       i["id"],
          label:    i["label"],
          selector: i["selector"],
          icon:     i["icon"],
          pinned:   i["pinned"] == true,
          section:  s["id"]
        )
      end
      Section.new(id: s["id"], label: s["label"], icon: s["icon"], items: items)
    end
    @by_id = @sections.flat_map(&:items).index_by(&:id)
  end

  def sections
    @sections
  end

  def find(id)
    @by_id[id.to_s]
  end

  def selectors_for(ids)
    ids.filter_map { |id| @by_id[id.to_s]&.selector }
  end

  def all_ids
    @by_id.keys
  end

  def pinned
    @by_id.values.select(&:pinned)
  end

  def as_json(*)
    {
      sections: @sections.map do |s|
        {
          id: s.id, label: s.label, icon: s.icon,
          items: s.items.map { |i| { id: i.id, label: i.label, icon: i.icon, pinned: i.pinned } }
        }
      end
    }
  end
end
