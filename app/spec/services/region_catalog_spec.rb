require "rails_helper"

RSpec.describe RegionCatalog do
  let(:fixtures_dir) { Rails.root.join("spec/fixtures/regions") }

  describe ".load_dir" do
    it "loads all .env files into Region objects" do
      catalog = RegionCatalog.load_dir(fixtures_dir)
      expect(catalog.names).to contain_exactly("single", "multi")
    end

    it "exposes single-region attributes" do
      catalog = RegionCatalog.load_dir(fixtures_dir)
      region  = catalog.find("single")
      expect(region.name).to eq("single")
      expect(region.label).to eq("Test Berlin")
      expect(region.country_code).to eq("de")
      expect(region.pbf_urls).to eq(["https://example.test/berlin.osm.pbf"])
      expect(region.default_view).to eq(lat: 52.52, lon: 13.4, zoom: 11)
      expect(region.multi?).to be(false)
    end

    it "exposes multi-region attributes" do
      catalog = RegionCatalog.load_dir(fixtures_dir)
      region  = catalog.find("multi")
      expect(region.pbf_urls).to eq([
        "https://example.test/de.osm.pbf",
        "https://example.test/at.osm.pbf"
      ])
      expect(region.multi?).to be(true)
    end

    it "raises Region::NotFound for missing names" do
      catalog = RegionCatalog.load_dir(fixtures_dir)
      expect { catalog.find("nope") }.to raise_error(RegionCatalog::Region::NotFound)
    end
  end

  describe "EnvParser" do
    it "parses KEY=value pairs" do
      input  = "KEY=value\nFOO=bar\n"
      result = RegionCatalog::EnvParser.parse(input)
      expect(result).to eq("KEY" => "value", "FOO" => "bar")
    end

    it "strips inline comments and blank lines" do
      input  = "# comment\n\nKEY=value\n"
      result = RegionCatalog::EnvParser.parse(input)
      expect(result).to eq("KEY" => "value")
    end

    it "unquotes double-quoted values" do
      input  = 'LABEL="Berlin (city)"' + "\n"
      result = RegionCatalog::EnvParser.parse(input)
      expect(result).to eq("LABEL" => "Berlin (city)")
    end
  end
end
