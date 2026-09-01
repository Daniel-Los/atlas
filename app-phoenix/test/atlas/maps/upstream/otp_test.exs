defmodule Atlas.Maps.Upstream.OtpTest do
  use ExUnit.Case, async: true
  alias Atlas.Maps.Upstream.{Client, Otp}

  setup do
    bypass = Bypass.open()
    {:ok, bypass: bypass, req: Client.build("http://localhost:#{bypass.port}")}
  end

  test "plan/2 posts a planConnection GraphQL request with required variables", %{
    bypass: bypass,
    req: req
  } do
    Bypass.expect_once(bypass, "POST", "/otp/gtfs/v1", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      payload = Jason.decode!(body)

      assert Plug.Conn.get_req_header(conn, "content-type") == ["application/json"]
      assert payload["query"] =~ "planConnection"

      assert payload["variables"]["origin"]["location"]["coordinate"] == %{
               "latitude" => 52.5,
               "longitude" => 13.4
             }

      assert payload["variables"]["destination"]["location"]["coordinate"] == %{
               "latitude" => 52.6,
               "longitude" => 13.5
             }

      assert payload["variables"]["dateTime"] == %{"earliestDeparture" => "2026-05-29T08:30:00Z"}
      assert payload["variables"]["modes"]["direct"] == ["WALK"]
      assert payload["variables"]["modes"]["transit"]["transit"] == [%{"mode" => "BUS"}]

      Plug.Conn.resp(conn, 200, ~s({"data":{"planConnection":{"edges":[]}}}))
    end)

    assert {:ok, %{"plan" => %{"itineraries" => []}}} =
             Otp.plan(req,
               from: %{lat: 52.5, lon: 13.4},
               to: %{lat: 52.6, lon: 13.5},
               date: "2026-05-29",
               time: "08:30:00",
               modes: "BUS,WALK"
             )
  end

  test "default/0 falls back to OTP port 8080 (not 8003)" do
    System.delete_env("OTP_URL")
    req = Otp.default()
    assert req.options.base_url == "http://localhost:8080"
  end
end
