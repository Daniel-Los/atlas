require "rails_helper"

RSpec.describe ControlPlaneClient do
  let(:stubs) { Faraday::Adapter::Test::Stubs.new }
  let(:conn)  { Faraday.new { |b| b.adapter :test, stubs; b.response :json } }
  subject     { described_class.new(connection: conn) }

  describe "#status" do
    it "returns parsed body on 200" do
      stubs.get("/status") { [200, {}, [{ "name" => "photon", "ready" => true }]] }
      expect(subject.status).to eq([{ "name" => "photon", "ready" => true }])
    end

    it "raises ControlPlane::Unavailable on connection failure" do
      stubs.get("/status") { raise Faraday::ConnectionFailed, "boom" }
      expect { subject.status }.to raise_error(ControlPlaneClient::Unavailable, /boom/)
    end

    it "raises ControlPlane::BadResponse on 5xx" do
      stubs.get("/status") { [502, {}, { "error" => { "code" => "X", "message" => "x" } }] }
      expect { subject.status }.to raise_error(ControlPlaneClient::BadResponse, /502/)
    end
  end

  describe "#enable!" do
    it "POSTs to /actions/services/:name/enable" do
      stubs.post("/actions/services/photon/enable") { [202, {}, ""] }
      expect(subject.enable!("photon")).to eq(true)
    end
  end

  describe "#disable!" do
    it "POSTs to /actions/services/:name/disable" do
      stubs.post("/actions/services/photon/disable") { [202, {}, ""] }
      expect(subject.disable!("photon")).to eq(true)
    end
  end

  describe "#update!" do
    it "POSTs update_kind to /actions/services/:name/update" do
      stubs.post("/actions/services/photon/update") do |env|
        expect(JSON.parse(env.body)).to eq("update_kind" => "full_refresh")
        [202, {}, ""]
      end
      expect(subject.update!("photon", update_kind: "full_refresh")).to eq(true)
    end
  end

  describe "#update_status" do
    it "returns parsed body for running update" do
      stubs.get("/actions/services/photon/update") { [200, {}, { "status" => "running", "kind" => "full_refresh" }] }
      expect(subject.update_status("photon")).to include("status" => "running")
    end

    it "returns idle when no run recorded" do
      stubs.get("/actions/services/photon/update") { [200, {}, { "status" => "idle" }] }
      expect(subject.update_status("photon")).to eq("status" => "idle")
    end
  end

  describe "#apply_regions" do
    it "POSTs regions array" do
      stubs.post("/actions/regions") do |env|
        expect(JSON.parse(env.body)).to eq("regions" => ["berlin", "vienna"])
        [202, {}, ""]
      end
      expect(subject.apply_regions(%w[berlin vienna])).to eq(true)
    end
  end

  describe "#download_tiles" do
    it "POSTs tile URL" do
      stubs.post("/actions/tiles") do |env|
        expect(JSON.parse(env.body)).to eq("url" => "https://t.example/p.pmtiles")
        [202, {}, ""]
      end
      expect(subject.download_tiles!("https://t.example/p.pmtiles")).to eq(true)
    end
  end
end
