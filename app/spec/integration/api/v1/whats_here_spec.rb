require "swagger_helper"

RSpec.describe "Api::V1::WhatsHere", type: :request do
  path "/api/v1/whats-here" do
    get "Reverse + nearby POIs in a radius" do
      tags "POIs"
      produces "application/json"
      description <<~MD
        Combines `ReverseOrchestrator` (Photon reverse + Placeholder admin enrichment) with an
        Overpass radius query so a single call answers “what is at and around this point”.
      MD

      parameter name: :lat,    in: :query, schema: { type: :number, format: :double }, required: true,  example: 52.5163
      parameter name: :lon,    in: :query, schema: { type: :number, format: :double }, required: true,  example: 13.3777
      parameter name: :radius, in: :query, schema: { type: :integer, minimum: 10, maximum: 2000, default: 200 }, required: false
      parameter name: :lang,   in: :query, schema: { type: :string }, required: false

      response "200", "label + nearby POIs" do
        schema "$ref" => "#/components/schemas/WhatsHereResponse"
        let(:lat) { 52.5163 }
        let(:lon) { 13.3777 }

        before do
          fake_reverse = ReverseOrchestrator::Result.new(
            feature: { "id" => "node:1", "label" => "Berlin", "coords" => { "lat" => lat, "lon" => lon } },
            admin: {},
            upstream_status: "ok"
          )
          allow_any_instance_of(ReverseOrchestrator).to receive(:lookup).and_return(fake_reverse)
          allow_any_instance_of(OverpassClient).to receive(:around).and_return({ "elements" => [] })
        end

        run_test!
      end

      response "400", "missing coordinates" do
        schema "$ref" => "#/components/schemas/ErrorEnvelope"
        let(:lat) { nil }
        let(:lon) { 13.3777 }
        run_test!
      end
    end
  end
end
