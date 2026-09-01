require "swagger_helper"

RSpec.describe "Api::V1::Search", type: :request do
  path "/api/v1/search" do
    get "Forward geocoding (autocomplete + admin enrichment)" do
      tags "Geocoding"
      produces "application/json"
      description <<~MD
        Sequential pipeline:
        1. **libpostal** normalizes the query.
        2. **Photon** returns ranked candidates.
        3. **Placeholder** fills in missing admin chain (country / state / city) per candidate.

        Returns gracefully when Photon is down: `data: []`, `meta.upstream: "unavailable"`.
      MD

      parameter name: :q,     in: :query, schema: { type: :string }, required: true,  example: "Marienplatz"
      parameter name: :limit, in: :query, schema: { type: :integer, minimum: 1, maximum: 25, default: 8 }, required: false
      parameter name: :lang,  in: :query, schema: { type: :string }, required: false, example: "de"
      parameter name: :lat,   in: :query, schema: { type: :number, format: :double }, required: false, description: "Optional proximity bias"
      parameter name: :lon,   in: :query, schema: { type: :number, format: :double }, required: false

      response "200", "results returned (possibly empty)" do
        schema "$ref" => "#/components/schemas/SearchResponse"
        let(:q) { "berlin" }
        run_test!
      end

      response "400", "missing q parameter" do
        schema "$ref" => "#/components/schemas/ErrorEnvelope"
        let(:q) { "" }
        run_test!
      end
    end
  end
end
