require "rails_helper"

RSpec.describe OtpClient do
  let(:from)  { { lat: 52.5163, lon: 13.3777 } }
  let(:to)    { { lat: 52.5219, lon: 13.4136 } }
  let(:stubs) { Faraday::Adapter::Test::Stubs.new }
  let(:conn)  { Faraday.new { |b| b.adapter :test, stubs; b.response :json, content_type: /\bjson$/ } }

  subject { described_class.new(base_url: "http://localhost:8080").tap { |c| c.instance_variable_set(:@conn, conn) } }

  it "calls /otp/routers/default/plan with formatted fromPlace/toPlace/date/time" do
    captured = nil
    stubs.get("/otp/routers/default/plan") do |env|
      captured = env.params
      [200, { "Content-Type" => "application/json" }, { plan: { itineraries: [] } }.to_json]
    end

    subject.plan(from: from, to: to, time: Time.new(2026, 5, 15, 10, 30, 0))
    expect(captured).to include(
      "fromPlace" => "52.5163,13.3777",
      "toPlace"   => "52.5219,13.4136",
      "date"      => "2026-05-15",
      "time"      => "10:30:00"
    )
  end

  it "raises Unavailable on connection failure" do
    stubs.get("/otp/routers/default/plan") { raise Faraday::ConnectionFailed, "refused" }
    expect { subject.plan(from: from, to: to) }
      .to raise_error(UpstreamService::Unavailable, /OTP unreachable/)
  end

  it "raises BadResponse on OTP error envelope in body" do
    stubs.get("/otp/routers/default/plan") do
      [200, { "Content-Type" => "application/json" }, { error: { msg: "No transit found" } }.to_json]
    end
    expect { subject.plan(from: from, to: to) }
      .to raise_error(UpstreamService::BadResponse, /No transit found/)
  end
end
