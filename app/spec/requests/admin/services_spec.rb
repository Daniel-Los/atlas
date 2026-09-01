require "rails_helper"

RSpec.describe "Admin::Services", type: :request do
  before do
    stub_const("ADMIN_CHECK_OK", true)
    ENV["ADMIN_USERNAME"] = "admin"
    ENV["ADMIN_PASSWORD"] = "x"
    Service.create!(name: "photon", profile: "geocoding", enabled: false, status: :stopped)
  end

  after do
    ENV.delete("ADMIN_USERNAME")
    ENV.delete("ADMIN_PASSWORD")
  end

  let(:auth) { { "HTTP_AUTHORIZATION" => ActionController::HttpAuthentication::Basic.encode_credentials("admin", "x") } }

  describe "GET /admin/services" do
    it "renders the panel with each known service" do
      get "/admin/services", headers: auth
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("photon")
    end
  end

  describe "POST /admin/services/:name (enabled=true)" do
    it "updates AR and calls sidecar enable!" do
      sidecar = stub_sidecar { |s| expect(s).to receive(:enable!).with("photon").and_return(true) }
      post "/admin/services/photon", params: { enabled: "true" }, headers: auth
      expect(response).to have_http_status(:ok)
      expect(Service.find_by(name: "photon").enabled).to be(true)
    end
  end

  describe "POST /admin/services/:name (enabled=false)" do
    it "calls sidecar disable! and flips AR" do
      Service.find_by(name: "photon").update!(enabled: true)
      stub_sidecar { |s| expect(s).to receive(:disable!).with("photon").and_return(true) }
      post "/admin/services/photon", params: { enabled: "false" }, headers: auth
      expect(Service.find_by(name: "photon").enabled).to be(false)
    end
  end

  describe "when sidecar unavailable" do
    it "renders 503 and leaves AR untouched" do
      stub_sidecar { |s| expect(s).to receive(:enable!).and_raise(ControlPlaneClient::Unavailable.new("down")) }
      post "/admin/services/photon", params: { enabled: "true" }, headers: auth
      expect(response).to have_http_status(:service_unavailable)
      expect(Service.find_by(name: "photon").enabled).to be(false)
    end
  end

  describe "GET /admin/services (full panel)" do
    before do
      Service.create!(name: "valhalla", profile: "routing", enabled: false, status: :stopped)
    end

    it "renders one card per service inside the settings panel" do
      get "/admin/services", headers: auth
      # The standalone /admin/services page renders the same settings_panel
      # partial used in the map's side panel. Verify the inner sections
      # (regions controller is always present in that panel).
      expect(response.body).to include('data-controller="regions"')
      expect(response.body).to include('id="service_photon"')
      expect(response.body).to include('id="service_valhalla"')
    end

    it "renders region chips" do
      get "/admin/services", headers: auth
      expect(response.body).to include('data-controller="regions"')
    end
  end
end
