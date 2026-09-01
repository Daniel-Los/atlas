require "swagger_helper"

RSpec.describe "Api::V1::Reverse", type: :request do
  path "/api/v1/reverse" do
    get "Reverse geocoding (point → labeled feature + admin chain)" do
      tags "Geocoding"
      produces "application/json"
      description <<~MD
        Sequential pipeline:
        1. **Photon** reverse → nearest labeled feature + its own admin tags.
        2. **Placeholder** fills in missing admin chain when Photon's tags are thin.
      MD

      parameter name: :lat,  in: :query, schema: { type: :number, format: :double }, required: true,  example: 52.5163
      parameter name: :lon,  in: :query, schema: { type: :number, format: :double }, required: true,  example: 13.3777
      parameter name: :lang, in: :query, schema: { type: :string }, required: false, example: "de"

      response "200", "feature returned (may be null if no nearby OSM feature)" do
        schema "$ref" => "#/components/schemas/ReverseResponse"
        let(:lat) { 52.5163 }
        let(:lon) { 13.3777 }
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
