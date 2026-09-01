require "rails_helper"

RSpec.describe "admin/services/_service_card.html.erb", type: :view do
  def render_card(service)
    render partial: "admin/services/service_card", locals: { service: service }
  end

  it "renders the service name and status" do
    svc = Service.create!(name: "photon", profile: "geocoding", status: "ready", phase: "ready")
    render_card(svc)
    expect(rendered).to include("photon")
    expect(rendered).to include("ready")
  end

  it "renders last_log as a truncated muted line when present" do
    svc = Service.create!(name: "photon", profile: "geocoding", status: "starting", last_log: "Booting up")
    render_card(svc)
    expect(rendered).to include("Booting up")
  end

  it "renders last_error in error styling when set" do
    svc = Service.create!(name: "overpass", profile: "pois", status: "error", last_error: "Boom")
    render_card(svc)
    expect(rendered).to match(/text-error.*Boom|Boom.*text-error/m)
  end

  it "falls back to last_log as error when status is error and log looks like a failure" do
    svc = Service.create!(name: "overpass", profile: "pois", status: "error",
                          last_log: "Failed to process planet file")
    render_card(svc)
    expect(rendered).to include("Failed to process planet file")
    expect(rendered).to match(/text-error/)
  end

  it "renders disk usage when positive" do
    svc = Service.create!(name: "photon", profile: "geocoding", status: "ready", disk_bytes: 180_000_000)
    render_card(svc)
    expect(rendered).to match(/171\.\d MB|172 MB|180 MB/)
  end

  it "omits disk row when zero" do
    svc = Service.create!(name: "libpostal", profile: "geocoding", status: "ready", disk_bytes: 0)
    render_card(svc)
    # The current-disk badge in the card header should render an em-dash, not a human size.
    # The dataset disk-impact line in the Updates section legitimately mentions MB; scope
    # the assertion to the explicit disk-bytes column container instead.
    expect(rendered).to include("tabular-nums w-16 text-right")
    expect(rendered).to match(/w-16 text-right">\s*—\s*</)
  end
end
