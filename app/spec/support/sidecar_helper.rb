require "net/http"
require "uri"

module SidecarHelper
  def stub_sidecar(client_class: ControlPlaneClient, &block)
    fake = instance_double(client_class)
    allow(client_class).to receive(:default).and_return(fake)
    block.call(fake) if block_given?
    fake
  end

  def boot_mock_sidecar(scenario)
    binary = ENV.fetch("ATLAS_CONTROL_MOCK_BIN", File.expand_path("../../../atlas-control/mock", __dir__))
    scenario_path = File.expand_path("../../../atlas-control/testdata/scenarios/#{scenario}.yml", __dir__)
    port = (Random.rand(20_000..50_000)).to_s
    pid = Process.spawn(binary, "--scenario", scenario_path, "--addr", ":#{port}", out: "/dev/null", err: "/dev/null")
    at_exit { Process.kill("TERM", pid) rescue nil }
    url = "http://127.0.0.1:#{port}"
    10.times do
      begin
        return url if Net::HTTP.get_response(URI("#{url}/healthz")).code == "200"
      rescue Errno::ECONNREFUSED
        sleep 0.1
      end
    end
    raise "mock sidecar did not become healthy"
  end
end

RSpec.configure do |c|
  c.include SidecarHelper, type: :request
  c.include SidecarHelper, type: :job
end
