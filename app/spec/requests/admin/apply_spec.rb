require "rails_helper"

RSpec.describe "Admin::Apply", type: :request do
  before do
    stub_const("ADMIN_CHECK_OK", true)
    ENV["ADMIN_USERNAME"] = "admin"
    ENV["ADMIN_PASSWORD"] = "x"

    fake_region = RegionCatalog::Region.new(
      name: "berlin", label: "Berlin", country_code: "de",
      pbf_urls: ["https://x/b.osm.pbf"], default_view: {})
    fake_catalog = instance_double(RegionCatalog, names: ["berlin"])
    allow(fake_catalog).to receive(:find).with("berlin").and_return(fake_region)
    allow(RegionCatalog).to receive(:load_dir).and_return(fake_catalog)

    RegionSelection.create!(region_name: "berlin", active: true, position: 0)
    Service.create!(name: "photon", profile: "geocoding", enabled: true)
  end

  after do
    ENV.delete("ADMIN_USERNAME")
    ENV.delete("ADMIN_PASSWORD")
  end

  let(:auth) { { "HTTP_AUTHORIZATION" => ActionController::HttpAuthentication::Basic.encode_credentials("admin", "x") } }

  describe "without confirmed=true" do
    it "returns 409 with the projection in the response body" do
      post "/admin/apply", headers: auth
      expect(response).to have_http_status(:conflict)
      expect(response.body).to match(/disk_gb/i)
    end
  end

  describe "with confirmed=true" do
    it "calls sidecar apply_regions for the active selection" do
      stub_sidecar do |s|
        expect(s).to receive(:apply_regions).with(["berlin"]).and_return(true)
      end
      post "/admin/apply", params: { confirmed: "true" }, headers: auth
      expect(response).to have_http_status(:accepted)
    end

    it "surfaces sidecar failures with 502" do
      stub_sidecar do |s|
        expect(s).to receive(:apply_regions).and_raise(ControlPlaneClient::BadResponse.new("502"))
      end
      post "/admin/apply", params: { confirmed: "true" }, headers: auth
      expect(response).to have_http_status(:bad_gateway)
    end
  end
end
