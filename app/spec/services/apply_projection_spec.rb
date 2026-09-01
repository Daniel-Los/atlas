require "rails_helper"

RSpec.describe ApplyProjection do
  let(:berlin) {
    RegionCatalog::Region.new(name: "berlin", label: "Berlin", country_code: "de",
                              pbf_urls: ["https://x/berlin.osm.pbf"],
                              default_view: {})
  }
  let(:germany) {
    RegionCatalog::Region.new(name: "germany", label: "Germany", country_code: "de",
                              pbf_urls: ["https://x/germany-latest.osm.pbf"],
                              default_view: {})
  }

  describe "#summary" do
    it "estimates per-tool sizes for a single city" do
      proj = ApplyProjection.new(regions: [berlin], services: %w[photon valhalla overpass])
      sum  = proj.summary

      expect(sum.total_disk_gb).to be > 0
      expect(sum.lines.map { |l| l[:name] }).to include("photon", "valhalla", "overpass")
    end

    it "scales for a country region" do
      city_proj    = ApplyProjection.new(regions: [berlin],  services: %w[overpass])
      country_proj = ApplyProjection.new(regions: [germany], services: %w[overpass])

      expect(country_proj.summary.total_disk_gb).to be > city_proj.summary.total_disk_gb
    end

    it "describes time as worst-case longest service" do
      proj = ApplyProjection.new(regions: [germany], services: %w[photon overpass])
      sum  = proj.summary
      expect(sum.first_boot_hours).to be >= 4   # Overpass dominates
    end

    it "returns zero for an empty selection" do
      proj = ApplyProjection.new(regions: [], services: [])
      expect(proj.summary.total_disk_gb).to eq(0)
    end
  end
end
