require "swagger_helper"

RSpec.describe "Api::V1::Reverse#batch", type: :request do
  path "/api/v1/reverse/batch" do
    post "Batch reverse geocoding (cached, grid-snapped)" do
      tags "Geocoding"
      consumes "application/json"
      produces "application/json"
      description <<~MD
        Reverse-geocode many coordinates in one round trip.

        * **Coords are snapped to a ~11 m grid** (4 decimal places) when computing the cache key,
          so repeated lookups of points within ~11 m of each other share a result.
        * **Solid Cache** (Rails 8 default) memoizes results for 30 days — dawarich-style trip
          replays after the first run hit cache nearly 100%.
        * Hard cap: 500 coords per request. For larger inputs, page client-side.
        * Each result preserves the caller's optional `id` so clients can correlate.
      MD

      parameter name: :payload, in: :body, schema: { "$ref" => "#/components/schemas/BatchReverseRequest" }

      response "200", "batch results" do
        schema "$ref" => "#/components/schemas/BatchReverseResponse"
        let(:payload) do
          { coords: [
              { id: "p1", lat: 52.5163, lon: 13.3777 },
              { id: "p2", lat: 48.1374, lon: 11.5755 }
            ],
            lang: "en" }
        end
        run_test!
      end

      response "400", "missing or invalid coords array" do
        schema "$ref" => "#/components/schemas/ErrorEnvelope"
        let(:payload) { { lang: "en" } }
        run_test!
      end

      response "422", "exceeds MAX_COORDS limit" do
        # Per-coord parse errors are NON-fatal (returned in the row's `error` field);
        # only structural problems like exceeding the 500-coord cap surface as 422.
        schema "$ref" => "#/components/schemas/ErrorEnvelope"
        let(:payload) do
          { coords: Array.new(BatchReverseGeocoder::MAX_COORDS + 1) { |i| { id: "p#{i}", lat: 52.0, lon: 13.0 } } }
        end
        run_test!
      end
    end
  end
end
