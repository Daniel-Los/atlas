require "rails_helper"

RSpec.describe ControlPlane::AutoUpdateScanJob do
  let(:client) { instance_double(ControlPlaneClient) }
  let(:photon) do
    Service.create!(
      name: "photon", profile: "geocoding",
      auto_update_enabled: true, last_update_status: nil,
      last_update_check_at: Time.utc(2026, 5, 17, 2, 50)
    )
  end
  let(:overpass) do
    Service.create!(
      name: "overpass", profile: "pois",
      auto_update_enabled: true
    )
  end

  describe "#perform" do
    it "calls the sidecar for a service whose schedule has elapsed" do
      photon # eager create
      allow(client).to receive(:update!).and_return(true)
      # Photon's default schedule is "0 3 * * 0" (Sun 03:00). Pick a Sunday 03:01 after the prior check.
      sunday_morning = Time.utc(2026, 5, 17, 3, 1) # 2026-05-17 is a Sunday
      described_class.new(client: client, now: sunday_morning).perform

      expect(client).to have_received(:update!).with("photon", update_kind: "full_refresh")
      expect(photon.reload.last_update_status).to eq("running")
    end

    it "skips services whose schedule has not yet elapsed" do
      photon.update!(last_update_check_at: Time.utc(2026, 5, 17, 3, 30))
      allow(client).to receive(:update!)

      # Same Sunday at 03:31 — already past this week's tick, photon was checked at 03:30, next due in a week.
      described_class.new(client: client, now: Time.utc(2026, 5, 17, 3, 31)).perform

      expect(client).not_to have_received(:update!)
    end

    it "skips @continuous services even when armed" do
      overpass.update!(last_update_check_at: nil)
      allow(client).to receive(:update!)

      described_class.new(client: client).perform

      expect(client).not_to have_received(:update!)
    end

    it "skips services in failure kill-switch state" do
      photon.update!(last_update_status: "failure")
      allow(client).to receive(:update!)

      described_class.new(client: client, now: Time.utc(2026, 5, 17, 3, 1)).perform

      expect(client).not_to have_received(:update!)
    end

    it "fires the kill-switch when the sidecar is unavailable" do
      photon # eager
      allow(client).to receive(:update!).and_raise(ControlPlaneClient::Unavailable, "boom")

      described_class.new(client: client, now: Time.utc(2026, 5, 17, 3, 1)).perform

      photon.reload
      expect(photon.last_update_status).to eq("failure")
      expect(photon.auto_update_enabled).to be false
      expect(photon.last_update_error).to eq("boom")
    end
  end
end
