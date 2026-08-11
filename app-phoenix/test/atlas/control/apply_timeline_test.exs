defmodule Atlas.Control.ApplyTimelineTest do
  use ExUnit.Case, async: true

  alias Atlas.Control.ApplyTimeline
  alias Atlas.Control.ApplyTimeline.Timeline

  @now ~U[2026-08-11 20:00:00Z]

  defp start_timeline(services \\ []) do
    ApplyTimeline.start(["Germany"], services, @now)
  end

  defp stage(%Timeline{stages: stages}, key), do: Enum.find(stages, &(&1.key == key))

  test "a fresh timeline lists the applier stages as pending" do
    timeline = start_timeline()

    assert timeline.status == :running
    assert timeline.regions == ["Germany"]
    assert timeline.current_step == 1
    assert Enum.map(timeline.stages, & &1.key) == [:download, :merge, :stage_otp, :convert]
    assert Enum.all?(timeline.stages, &(&1.state == :pending))
  end

  test "a download event opens a per-file row carrying label, source and bytes" do
    timeline =
      start_timeline()
      |> ApplyTimeline.apply_event(
        {:apply_progress,
         %{
           phase: :downloading,
           region: "germany",
           item: %{
             label: "germany-latest.osm.pbf",
             source: "https://download.geofabrik.de/europe/germany-latest.osm.pbf",
             current: 1024,
             total: 4096
           }
         }},
        @now
      )

    download = stage(timeline, :download)

    assert download.state == :running
    assert [item] = download.items
    assert item.label == "germany-latest.osm.pbf"
    assert item.source == "https://download.geofabrik.de/europe/germany-latest.osm.pbf"
    assert item.measure.kind == :bytes
    assert item.measure.current == 1024
    assert item.measure.total == 4096
  end

  test "a second file becomes a second row, and the first is marked done" do
    timeline =
      start_timeline()
      |> ApplyTimeline.apply_event(
        {:apply_progress,
         %{phase: :downloading, region: "germany",
           item: %{label: "a.pbf", source: "http://x/a.pbf", current: 10, total: 10}}},
        @now
      )
      |> ApplyTimeline.apply_event(
        {:apply_progress,
         %{phase: :downloading, region: "austria",
           item: %{label: "b.pbf", source: "http://x/b.pbf", current: 5, total: 20}}},
        @now
      )

    assert [a, b] = stage(timeline, :download).items
    assert a.label == "a.pbf"
    assert a.state == :done
    assert b.label == "b.pbf"
    assert b.state == :running
  end

  test "an unknown total yields an indeterminate measure, never a fraction" do
    timeline =
      start_timeline()
      |> ApplyTimeline.apply_event(
        {:apply_progress,
         %{phase: :downloading, region: "germany",
           item: %{label: "a.pbf", source: "http://x/a.pbf", current: 999, total: nil}}},
        @now
      )

    assert [item] = stage(timeline, :download).items
    assert item.measure.total == nil
    refute ApplyTimeline.percentage(item.measure)
  end
end
