defmodule Atlas.Maps.BasemapPresetsTest do
  use ExUnit.Case, async: true

  alias Atlas.Maps.BasemapPresets

  describe "protomaps_daily_url/1" do
    test "targets the previous day's build, which is already published" do
      assert BasemapPresets.protomaps_daily_url(~D[2026-05-21]) ==
               "https://build.protomaps.com/20260520.pmtiles"
    end

    test "rolls back across a month boundary" do
      assert BasemapPresets.protomaps_daily_url(~D[2026-06-01]) ==
               "https://build.protomaps.com/20260531.pmtiles"
    end

    test "rolls back across a year boundary" do
      assert BasemapPresets.protomaps_daily_url(~D[2026-01-01]) ==
               "https://build.protomaps.com/20251231.pmtiles"
    end

    test "zero-pads single-digit months and days" do
      assert BasemapPresets.protomaps_daily_url(~D[2026-09-10]) ==
               "https://build.protomaps.com/20260909.pmtiles"
    end
  end

  describe "protomaps_daily_url/0" do
    test "resolves against the current UTC date" do
      expected = BasemapPresets.protomaps_daily_url(Date.utc_today())

      assert BasemapPresets.protomaps_daily_url() == expected
    end

    test "never points at today's build" do
      today = Date.utc_today()
      today_stamp = Calendar.strftime(today, "%Y%m%d")

      refute BasemapPresets.protomaps_daily_url() =~ today_stamp
    end
  end

  describe "preset metadata" do
    test "the protomaps note does not promise today's build" do
      note = Enum.find(BasemapPresets.all(), &(&1.id == "protomaps-planet-daily")).note

      refute note =~ "today",
             "the card note must not advertise a build the URL deliberately does not request"
    end
  end

  describe "resolve/1" do
    test "the protomaps preset resolves through the daily URL builder" do
      assert {:ok, %{url: url, download: true}} = BasemapPresets.resolve("protomaps-planet-daily")

      assert url == BasemapPresets.protomaps_daily_url()
    end
  end
end
