require "rails_helper"

RSpec.describe RegionSelection, type: :model do
  describe "validations" do
    it "requires a region_name" do
      expect(RegionSelection.new).not_to be_valid
    end

    it "enforces uniqueness on region_name" do
      RegionSelection.create!(region_name: "berlin", position: 0)
      duplicate = RegionSelection.new(region_name: "berlin", position: 1)
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:region_name]).to include("has already been taken")
    end
  end

  describe ".active_names" do
    it "returns active region names ordered by position" do
      RegionSelection.create!(region_name: "vienna",  active: true, position: 1)
      RegionSelection.create!(region_name: "berlin",  active: true, position: 0)
      RegionSelection.create!(region_name: "munich",  active: false, position: 2)

      expect(RegionSelection.active_names).to eq(%w[berlin vienna])
    end
  end

  describe "#orphaned?" do
    it "is false by default" do
      expect(RegionSelection.new(region_name: "berlin").orphaned?).to be(false)
    end
  end
end
