require "rails_helper"

RSpec.describe "admin/services/index.html.erb", type: :view do
  before do
    @regions = []
    @region_selection = []
    @active_regions = []
  end

  it "groups services under profile section headers in fixed order" do
    @services = [
      Service.create!(name: "photon",   profile: "geocoding", status: "ready"),
      Service.create!(name: "valhalla", profile: "routing",   status: "ready"),
      Service.create!(name: "overpass", profile: "pois",      status: "ready"),
      Service.create!(name: "otp",      profile: "transit",   status: "ready")
    ]
    render template: "admin/services/index"

    geocoding_pos = rendered.index("Geocoding")
    routing_pos   = rendered.index("Routing")
    pois_pos      = rendered.index("POIs")
    transit_pos   = rendered.index("Transit")

    expect(geocoding_pos).to be_present
    expect(routing_pos).to be > geocoding_pos
    expect(pois_pos).to be > routing_pos
    expect(transit_pos).to be > pois_pos
  end

  it "omits headers for profiles with no services" do
    @services = [Service.create!(name: "photon", profile: "geocoding", status: "ready")]
    render template: "admin/services/index"
    expect(rendered).to include("Geocoding")
    expect(rendered).not_to include("Routing")
    expect(rendered).not_to include("POIs")
    expect(rendered).not_to include("Transit")
  end
end
