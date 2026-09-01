require "rails_helper"

RSpec.describe Service, type: :model do
  describe "validations" do
    it "requires a name" do
      service = Service.new(profile: "geocoding")
      expect(service).not_to be_valid
      expect(service.errors[:name]).to include("can't be blank")
    end

    it "requires a unique name" do
      Service.create!(name: "photon", profile: "geocoding")
      duplicate = Service.new(name: "photon", profile: "geocoding")
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:name]).to include("has already been taken")
    end
  end

  describe "#status" do
    it "defaults to 'unknown'" do
      service = Service.new(name: "photon", profile: "geocoding")
      expect(service.status).to eq("unknown")
    end

    it "accepts the known states" do
      service = Service.new(name: "photon", profile: "geocoding")
      %w[unknown stopped starting downloading building ready error unhealthy].each do |state|
        service.status = state
        expect(service).to be_valid, "expected #{state} to be valid"
      end
    end

    it "rejects unknown statuses" do
      expect {
        Service.new(name: "photon", profile: "geocoding", status: "bogus")
      }.to raise_error(ArgumentError, /'bogus' is not a valid status/)
    end
  end

  describe "progress" do
    it "is between 0 and 1" do
      service = Service.new(name: "photon", profile: "geocoding", progress: 1.5)
      expect(service).not_to be_valid
      expect(service.errors[:progress]).to include("must be less than or equal to 1")
    end
  end

  describe "disk_bytes" do
    it "rejects negative values" do
      service = Service.new(name: "photon", profile: "geocoding", disk_bytes: -1)
      expect(service).not_to be_valid
      expect(service.errors[:disk_bytes]).to include("must be greater than or equal to 0")
    end
  end

  describe "dataset auto-update" do
    let(:photon)   { Service.create!(name: "photon",   profile: "geocoding") }
    let(:overpass) { Service.create!(name: "overpass", profile: "pois") }

    describe "#freshness_label" do
      it "renders the dataset_updated_at as 'Updated on YYYY-MM-DD, HH:MM UTC'" do
        photon.update!(dataset_updated_at: Time.utc(2026, 5, 11, 11, 36))
        expect(photon.freshness_label).to eq("Updated on 2026-05-11, 11:36 UTC")
      end

      it "returns 'Never updated' when blank" do
        expect(photon.freshness_label).to eq("Never updated")
      end
    end

    describe "#effective_schedule" do
      it "uses the override when present" do
        photon.update!(update_schedule_cron: "0 6 * * *")
        expect(photon.effective_schedule).to eq("0 6 * * *")
      end

      it "falls back to the YAML default" do
        expect(photon.effective_schedule).to eq("0 3 * * 0")
      end

      it "returns @continuous for diff-streamers like overpass" do
        expect(overpass.effective_schedule).to eq("@continuous")
      end
    end

    describe "#begin_update!" do
      it "marks status running and returns true on first call" do
        expect(photon.begin_update!).to be true
        photon.reload
        expect(photon.last_update_status).to eq("running")
        expect(photon.last_update_check_at).to be_within(1.second).of(Time.current)
      end

      it "returns false when an update is already running" do
        photon.update!(last_update_status: "running")
        expect(photon.begin_update!).to be false
      end
    end

    describe "#finish_update!" do
      before { photon.update!(last_update_status: "running") }

      it "records success and stamps dataset_updated_at" do
        photon.finish_update!(success: true, duration_s: 42)
        expect(photon.last_update_status).to eq("success")
        expect(photon.last_update_duration_s).to eq(42)
        expect(photon.dataset_updated_at).to be_within(1.second).of(Time.current)
      end

      it "silently disables auto-update on failure (kill switch)" do
        photon.update!(auto_update_enabled: true)
        photon.finish_update!(success: false, error: "kaboom", duration_s: 5)
        expect(photon.last_update_status).to eq("failure")
        expect(photon.auto_update_enabled).to be false
        expect(photon.last_update_error).to eq("kaboom")
      end
    end

    describe "#auto_update_armed?" do
      it "is false when failure kill-switch fired" do
        photon.update!(auto_update_enabled: true, last_update_status: "failure")
        expect(photon.auto_update_armed?).to be false
      end

      it "is true when enabled and not running/failed" do
        photon.update!(auto_update_enabled: true, last_update_status: "success")
        expect(photon.auto_update_armed?).to be true
      end
    end
  end
end
