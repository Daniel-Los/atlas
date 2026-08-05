defmodule Atlas.Maps.MapMatchTest do
  use ExUnit.Case, async: false

  alias Atlas.Maps.MapMatch
  alias Atlas.Maps.Upstream.Client

  # Verified against Atlas.Geometry.Polyline.decode(_, 6):
  #   LEG_A -> [{52.5, 13.4}, {52.51, 13.41}]
  #   LEG_B -> [{52.51, 13.41}, {52.52, 13.42}]
  # The legs deliberately share {52.51, 13.41} — Valhalla repeats the boundary
  # point in each leg, and a naive concatenation would emit it twice.
  @leg_a "_ajccB_{zpX_pR_pR"
  @leg_b "_r}ccB_lnqX_pR_pR"

  @shape [%{lat: 52.5, lon: 13.4}, %{lat: 52.51, lon: 13.41}, %{lat: 52.52, lon: 13.42}]

  setup do
    bypass = Bypass.open()
    System.put_env("VALHALLA_URL", "http://localhost:#{bypass.port}")
    on_exit(fn -> System.delete_env("VALHALLA_URL") end)
    {:ok, bypass: bypass}
  end

  defp respond(bypass, status, body) do
    Bypass.expect_once(bypass, "POST", "/trace_route", fn conn ->
      Plug.Conn.resp(conn, status, body)
    end)
  end

  describe "match/1" do
    test "normalises the trip envelope into a Result", %{bypass: bypass} do
      respond(bypass, 200, ~s({"trip":{"summary":{"length":2.5},"legs":[{"shape":"#{@leg_a}"}]}}))

      assert {:ok, result} = MapMatch.match(shape: @shape, mode: "auto")

      assert result.features.summary == %{"length" => 2.5}
      assert [%{"shape" => @leg_a}] = result.features.legs
      assert result.features.shape_format == "valhalla_encoded_polyline6"
      assert result.upstream_status == "ok"
    end

    test "rejects a trace with fewer than two points", %{bypass: _bypass} do
      assert {:error, :invalid, message, details} =
               MapMatch.match(shape: [%{lat: 52.5, lon: 13.4}], mode: "auto")

      assert message =~ "at least 2"
      assert details == %{param: "shape", min: 2}
    end

    test "rejects a trace over the point cap" do
      over = MapMatch.max_points() + 1
      shape = for _ <- 1..over, do: %{lat: 52.5, lon: 13.4}

      assert {:error, :too_many, max} = MapMatch.match(shape: shape, mode: "auto")
      assert max == MapMatch.max_points()
    end

    test "max_points/0 is overridable via MAP_MATCH_MAX_POINTS" do
      System.put_env("MAP_MATCH_MAX_POINTS", "7")
      on_exit(fn -> System.delete_env("MAP_MATCH_MAX_POINTS") end)

      assert MapMatch.max_points() == 7
    end
  end

  describe "geojson output" do
    test "decodes the legs into a single LineString of [lon, lat]", %{bypass: bypass} do
      respond(bypass, 200, ~s({"trip":{"summary":{},"legs":[{"shape":"#{@leg_a}"}]}}))

      assert {:ok, result} = MapMatch.match(shape: @shape, mode: "auto", format: "geojson")

      assert result.features.shape_format == "geojson"

      assert result.features.geometry == %{
               type: "LineString",
               coordinates: [[13.4, 52.5], [13.41, 52.51]]
             }

      # The encoded legs are redundant once decoded, and shipping both doubles
      # the payload for the exact consumer that asked not to decode anything.
      refute Map.has_key?(result.features, :legs)
    end

    test "joins consecutive legs without repeating the shared boundary point", %{bypass: bypass} do
      respond(
        bypass,
        200,
        ~s({"trip":{"summary":{},"legs":[{"shape":"#{@leg_a}"},{"shape":"#{@leg_b}"}]}})
      )

      assert {:ok, result} = MapMatch.match(shape: @shape, mode: "auto", format: "geojson")

      assert result.features.geometry.coordinates == [
               [13.4, 52.5],
               [13.41, 52.51],
               [13.42, 52.52]
             ]
    end
  end

  describe "upstream failures" do
    test "a 400 becomes a validation error, not a bad gateway", %{bypass: bypass} do
      # Valhalla answers 400 when the trace cannot be snapped (error_code 171,
      # "No suitable edges near location"). That is the caller's data being
      # unmatchable, not Atlas's upstream misbehaving — 502 would send the
      # operator hunting a healthy service.
      respond(bypass, 400, ~s({"error_code":171,"error":"No suitable edges near location"}))

      assert {:error, :invalid, message, details} = MapMatch.match(shape: @shape, mode: "auto")

      assert message =~ "could not be matched"
      assert details.param == "shape"
    end

    test "a 500 stays a BadResponse", %{bypass: bypass} do
      respond(bypass, 500, "boom")

      assert {:error, %Client.BadResponse{status: 500}} =
               MapMatch.match(shape: @shape, mode: "auto")
    end

    test "a dead upstream stays Unavailable", %{bypass: bypass} do
      Bypass.down(bypass)

      assert {:error, %Client.Unavailable{}} = MapMatch.match(shape: @shape, mode: "auto")
    end
  end
end
