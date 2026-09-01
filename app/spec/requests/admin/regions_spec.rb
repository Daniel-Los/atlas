require "rails_helper"

RSpec.describe "Admin::Regions", type: :request do
  before do
    stub_const("ADMIN_CHECK_OK", true)
    ENV["ADMIN_USERNAME"] = "admin"
    ENV["ADMIN_PASSWORD"] = "x"
  end

  after do
    ENV.delete("ADMIN_USERNAME")
    ENV.delete("ADMIN_PASSWORD")
  end

  let(:auth) { { "HTTP_AUTHORIZATION" => ActionController::HttpAuthentication::Basic.encode_credentials("admin", "x") } }

  before do
    fake_catalog = instance_double(RegionCatalog,
      names: %w[berlin germany],
      find: nil
    )
    allow(fake_catalog).to receive(:find) { |n| RegionCatalog::Region.new(name: n, label: n, country_code: "de", pbf_urls: [], default_view: {}) }
    allow(RegionCatalog).to receive(:load_dir).and_return(fake_catalog)
  end

  it "replaces selection in a single transaction" do
    RegionSelection.create!(region_name: "stale", active: true, position: 0)

    post "/admin/regions",
         params: { regions: ["berlin", "germany"] },
         headers: auth

    expect(response).to have_http_status(:ok)
    expect(RegionSelection.active_names).to eq(%w[berlin germany])
  end

  it "broadcasts region_meta and region_pill to region_channel" do
    targets = []
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to) do |stream, **opts|
      targets << [stream, opts[:target]]
    end

    post "/admin/regions", params: { regions: ["berlin"] }, headers: auth

    expect(targets).to include(["region_channel", "region_meta"])
    expect(targets).to include(["region_channel", "region_pill"])
  end

  it "rejects unknown regions" do
    fake_catalog = instance_double(RegionCatalog, names: %w[berlin germany])
    allow(fake_catalog).to receive(:find).with("berlin").and_return(RegionCatalog::Region.new(name: "berlin", label: "b", country_code: "de", pbf_urls: [], default_view: {}))
    allow(fake_catalog).to receive(:find).with("nope").and_raise(RegionCatalog::Region::NotFound.new("region 'nope' not in catalog"))
    allow(RegionCatalog).to receive(:load_dir).and_return(fake_catalog)

    post "/admin/regions", params: { regions: %w[berlin nope] }, headers: auth
    expect(response).to have_http_status(:unprocessable_entity)
  end
end
