require "swagger_helper"

RSpec.describe "Api::V1::Route", type: :request do
  path "/api/v1/route" do
    get "Routing via Valhalla (multimodal)" do
      tags "Routing"
      produces "application/json"
      description "Single-source endpoint — Valhalla returns a turn-by-turn route, summary, and (optional) elevation profile."

      parameter name: :from, in: :query, schema: { type: :string, pattern: '^-?\d+(\.\d+)?,-?\d+(\.\d+)?$' },
                required: true, example: "52.5163,13.3777", description: "lat,lon"
      parameter name: :to,   in: :query, schema: { type: :string, pattern: '^-?\d+(\.\d+)?,-?\d+(\.\d+)?$' },
                required: true, example: "48.1374,11.5755", description: "lat,lon"
      parameter name: :mode, in: :query, schema: { type: :string, enum: %w[auto bicycle pedestrian], default: "auto" },
                required: false

      response "200", "route returned" do
        schema "$ref" => "#/components/schemas/RouteResponse"
        let(:from) { "52.5163,13.3777" }
        let(:to)   { "48.1374,11.5755" }

        before do
          fake_response = {
            "trip" => {
              "summary" => { "length" => 1.2, "time" => 90 },
              "legs"    => [{ "shape" => "abc", "summary" => {}, "maneuvers" => [] }]
            }
          }
          allow_any_instance_of(ValhallaClient).to receive(:route).and_return(fake_response)
        end

        run_test!
      end

      response "503", "Valhalla unreachable" do
        schema "$ref" => "#/components/schemas/ErrorEnvelope"
        let(:from) { "52.5163,13.3777" }
        let(:to)   { "48.1374,11.5755" }
        run_test!
      end
    end
  end
end
