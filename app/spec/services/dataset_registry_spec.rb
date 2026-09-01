require "rails_helper"

RSpec.describe DatasetRegistry do
  describe ".default" do
    it "loads every service from config/datasets.yml" do
      registry = described_class.default
      expect(registry.names).to include("caddy", "photon", "valhalla", "overpass", "otp", "placeholder", "libpostal", "whosonfirst")
    end
  end

  describe DatasetRegistry::Entry do
    let(:registry) { described_class = DatasetRegistry.default }

    it "classifies photon as full_refresh" do
      entry = DatasetRegistry.default["photon"]
      expect(entry.full_refresh?).to be true
      expect(entry.continuous?).to be false
      expect(entry.default_schedule).to eq("0 3 * * 0")
    end

    it "classifies overpass as continuous incremental" do
      entry = DatasetRegistry.default["overpass"]
      expect(entry.incremental?).to be true
      expect(entry.continuous?).to be true
    end

    it "classifies caddy as image_only" do
      entry = DatasetRegistry.default["caddy"]
      expect(entry.image_only?).to be true
    end

    it "produces a human disk impact summary" do
      expect(DatasetRegistry.default["photon"].disk_impact_summary).to match(/Full refresh/i)
      expect(DatasetRegistry.default["overpass"].disk_impact_summary).to match(/Incremental/i)
      expect(DatasetRegistry.default["caddy"].disk_impact_summary).to match(/Image pull/i)
    end

    it "rejects unknown update_kind" do
      expect {
        DatasetRegistry::Entry.new("bad", { "update_kind" => "weird" })
      }.to raise_error(ArgumentError, /unknown update_kind/)
    end
  end
end
