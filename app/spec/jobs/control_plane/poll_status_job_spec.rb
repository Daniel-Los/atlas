require "rails_helper"

RSpec.describe ControlPlane::PollStatusJob, type: :job do
  let(:client) { instance_double(ControlPlaneClient) }

  before do
    Service.delete_all
    Service.create!(name: "photon", profile: "geocoding", status: :unknown)
    # The _service_card partial lands in Task 12; until then, intercept the render-and-broadcast call
    # and route through ActionCable.server.broadcast directly so the have_broadcasted_to matcher fires.
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to) do |stream, **_opts|
      ActionCable.server.broadcast(stream, "<turbo-stream></turbo-stream>")
    end
  end

  it "updates the service when sidecar reports new state" do
    allow(client).to receive(:status).and_return([
      { "name" => "photon", "container_state" => "running", "phase" => "downloading",
        "progress" => 0.42, "last_log_line" => "Download progress: 42%",
        "ready" => false, "disk_bytes" => 1_234_567 }
    ])

    described_class.new(client: client).perform_now

    photon = Service.find_by(name: "photon")
    expect(photon.status).to eq("downloading")
    expect(photon.phase).to eq("downloading")
    expect(photon.progress).to eq(0.42)
    expect(photon.disk_bytes).to eq(1_234_567)
  end

  it "broadcasts a Turbo Stream when state changes" do
    allow(client).to receive(:status).and_return([
      { "name" => "photon", "container_state" => "running", "phase" => "ready",
        "progress" => 1.0, "last_log_line" => "Photon ready",
        "ready" => true, "disk_bytes" => 8 * 1024**3 }
    ])

    expect {
      described_class.new(client: client).perform_now
    }.to have_broadcasted_to("services_channel").from_channel(Turbo::StreamsChannel)
  end

  it "is silent when sidecar is unreachable" do
    allow(client).to receive(:status).and_raise(ControlPlaneClient::Unavailable.new("down"))
    expect { described_class.new(client: client).perform_now }.not_to raise_error
  end

  it "creates services missing from AR when sidecar reports them" do
    allow(client).to receive(:status).and_return([
      { "name" => "valhalla", "container_state" => "running", "phase" => "building",
        "progress" => 0.1, "last_log_line" => "...", "ready" => false, "disk_bytes" => 0 }
    ])

    expect {
      described_class.new(client: client).perform_now
    }.to change { Service.where(name: "valhalla").count }.from(0).to(1)
  end
end
