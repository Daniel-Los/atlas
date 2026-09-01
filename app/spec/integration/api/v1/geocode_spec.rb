require "swagger_helper"

RSpec.describe "Api::V1::Geocode", type: :request do
  path "/api/v1/geocode" do
    get "Combined forward + reverse geocoding" do
      tags "Geocoding"
      produces "application/json"
      description <<~MD
        Unified entrypoint that auto-routes to forward or reverse:

        * `?q=…` (with optional `lat,lon` for proximity bias) → forward search.
        * `?lat=&lon=` only → reverse geocode.

        Internally calls the same orchestrators as `/api/v1/search` and `/api/v1/reverse`.
      MD

      parameter name: :q,     in: :query, schema: { type: :string }, required: false, example: "Marienplatz"
      parameter name: :lat,   in: :query, schema: { type: :number, format: :double }, required: false, example: 48.1374
      parameter name: :lon,   in: :query, schema: { type: :number, format: :double }, required: false, example: 11.5755
      parameter name: :limit, in: :query, schema: { type: :integer, minimum: 1, maximum: 25, default: 8 }, required: false
      parameter name: :lang,  in: :query, schema: { type: :string }, required: false

      response "200", "forward results" do
        schema "$ref" => "#/components/schemas/GeocodeResponse"
        let(:q)   { "berlin" }
        let(:lat) { nil }
        let(:lon) { nil }
        run_test!
      end

      response "200", "reverse result" do
        schema "$ref" => "#/components/schemas/GeocodeResponse"
        let(:q)   { nil }
        let(:lat) { 52.5163 }
        let(:lon) { 13.3777 }
        run_test!
      end

      response "400", "neither q nor lat/lon supplied" do
        schema "$ref" => "#/components/schemas/ErrorEnvelope"
        let(:q)   { nil }
        let(:lat) { nil }
        let(:lon) { nil }
        run_test!
      end
    end
  end
end
