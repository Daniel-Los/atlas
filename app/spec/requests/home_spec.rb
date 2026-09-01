require "rails_helper"

RSpec.describe "Home", type: :request do
  before do
    fake_catalog = instance_double(RegionCatalog)
    berlin = RegionCatalog::Region.new(
      name: "berlin", label: "Berlin (city)", country_code: "de",
      pbf_urls: [], default_view: { lat: 52.52, lon: 13.4, zoom: 11 }
    )
    allow(fake_catalog).to receive(:find).with("berlin").and_return(berlin)
    allow(fake_catalog).to receive(:find).and_raise(RegionCatalog::Region::NotFound)
    allow(fake_catalog).to receive(:all).and_return([berlin])
    allow(RegionCatalog).to receive(:load_dir).and_return(fake_catalog)
  end

  it "renders the map page with no active region by default" do
    get "/"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('id="region_pill"')
    expect(response.body).to include('id="region_meta"')
    # No badge text when there's no active region.
    expect(response.body).not_to include("badge-neutral")
  end

  it "shows region pill when a region is active" do
    RegionSelection.create!(region_name: "berlin", active: true, position: 0)
    get "/"
    expect(response.body).to include("Berlin")
    expect(response.body).to include("tap settings")
  end

  it "shows degradation banner when an enabled service is in error" do
    Service.create!(name: "valhalla", profile: "routing", enabled: true, status: "error")
    get "/"
    expect(response.body).to include("Routing unavailable")
  end

  it "suppresses banner when no enabled service is degraded" do
    Service.create!(name: "valhalla", profile: "routing", enabled: true, status: "ready")
    get "/"
    expect(response.body).not_to include("unavailable")
  end
end
