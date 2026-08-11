defmodule Atlas.Control.ApplyTimelineTest do
  use ExUnit.Case, async: false

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

  test "advancing to a later phase completes the earlier stages" do
    timeline =
      start_timeline()
      |> ApplyTimeline.apply_event({:apply_progress, %{phase: :downloading, region: "germany"}}, @now)
      |> ApplyTimeline.apply_event({:apply_progress, %{phase: :converting, region: nil}}, @now)

    assert stage(timeline, :download).state == :done
    assert stage(timeline, :merge).state == :done
    assert stage(timeline, :stage_otp).state == :done
    assert stage(timeline, :convert).state == :running
    assert timeline.current_step == 4
  end

  test "apply_done completes every remaining applier stage" do
    timeline =
      start_timeline()
      |> ApplyTimeline.apply_event({:apply_progress, %{phase: :downloading, region: "germany"}}, @now)
      |> ApplyTimeline.apply_event({:apply_done, %{}}, @now)

    assert timeline.status == :done
    assert timeline.finished_at == @now
    assert Enum.all?(timeline.stages, &(&1.state == :done))
  end

  test "apply_error marks the failing stage and skips the rest" do
    timeline =
      start_timeline()
      |> ApplyTimeline.apply_event({:apply_progress, %{phase: :converting, region: nil}}, @now)
      |> ApplyTimeline.apply_event(
        {:apply_error, %{phase: :converting, reason: "no space left on device"}},
        @now
      )

    assert timeline.status == :error
    assert stage(timeline, :convert).state == :error
    assert stage(timeline, :convert).error == "no space left on device"
    assert stage(timeline, :download).state == :done
  end

  test "apply_error on an early phase skips the untouched later stages" do
    timeline =
      start_timeline()
      |> ApplyTimeline.apply_event({:apply_progress, %{phase: :downloading, region: "germany"}}, @now)
      |> ApplyTimeline.apply_event(
        {:apply_error, %{phase: :downloading, reason: "network unreachable"}},
        @now
      )

    assert timeline.status == :error
    assert stage(timeline, :download).state == :error
    assert stage(timeline, :download).error == "network unreachable"
    assert stage(timeline, :merge).state == :skipped
    assert stage(timeline, :stage_otp).state == :skipped
    assert stage(timeline, :convert).state == :skipped
  end

  defp snapshot(name, fields) do
    Map.merge(
      %{name: name, status: :running, phase: nil, progress: nil, ready?: false, last_error: nil},
      fields
    )
  end

  test "an adopted service reports its ingest phase and real percentage" do
    timeline =
      start_timeline(["valhalla"])
      |> ApplyTimeline.apply_event({:apply_progress, %{phase: :restarting}}, @now)
      |> ApplyTimeline.apply_event(
        {:service_update, snapshot("valhalla", %{phase: "building-tiles", progress: 0.34})},
        @now
      )

    valhalla = stage(timeline, :valhalla)

    assert valhalla.state == :running
    assert valhalla.detail == "building-tiles"
    assert ApplyTimeline.percentage(valhalla.measure) == 34
  end

  test "a service reporting ready completes its stage" do
    timeline =
      start_timeline(["overpass"])
      |> ApplyTimeline.apply_event({:apply_progress, %{phase: :restarting}}, @now)
      |> ApplyTimeline.apply_event(
        {:service_update, snapshot("overpass", %{phase: "ready", ready?: true})},
        @now
      )

    assert stage(timeline, :overpass).state == :done
  end

  test "a service this job never restarted is not adopted" do
    timeline =
      start_timeline(["valhalla"])
      |> ApplyTimeline.apply_event(
        {:service_update, snapshot("overpass", %{phase: "ingesting"})},
        @now
      )

    assert stage(timeline, :overpass) == nil

    assert Enum.map(timeline.stages, & &1.key) ==
             [:download, :merge, :stage_otp, :convert, :valhalla]
  end

  test "a failing service errors its stage" do
    timeline =
      start_timeline(["otp"])
      |> ApplyTimeline.apply_event({:apply_progress, %{phase: :restarting}}, @now)
      |> ApplyTimeline.apply_event(
        {:service_update, snapshot("otp", %{status: :error, last_error: "OOM"})},
        @now
      )

    assert stage(timeline, :otp).state == :error
    assert stage(timeline, :otp).error == "OOM"
  end

  test "a service name outside the known ingest set is ignored entirely" do
    # "photon" is a real Atlas service (see Atlas.Control.Parsers.Photon) but
    # is not one of the three services a region apply can restart, so it is
    # not a key in `ApplyTimeline`'s service map. Deliberately never written
    # as the atom `:photon` anywhere else in this file — unlike "valhalla" /
    # "overpass" / "otp", which this file's own other tests already turn
    # into atoms via `stage(timeline, :valhalla)` and friends, making them
    # exist in the atom table before any test body runs. That pre-existence
    # is exactly what let a prior implementation's `String.to_existing_atom/1`
    # pass every test here while still being able to raise `ArgumentError` in
    # production on a genuine fresh-boot first sighting of a known service
    # name. This test's name carries no such pre-existing atom, so it
    # actually exercises the "unrecognized name" branch as plain string
    # comparison — proving the miss path never touches the atom table at
    # all, regardless of what has or hasn't run before it.
    timeline = start_timeline()

    result =
      ApplyTimeline.apply_event(
        timeline,
        {:service_update, snapshot("photon", %{phase: "extracting", progress: 0.5})},
        @now
      )

    assert result == timeline
  end

  describe "server" do
    test "broadcasts a timeline and answers current/0" do
      start_supervised!(Atlas.Control.ApplyTimeline)
      Phoenix.PubSub.subscribe(Atlas.PubSub, ApplyTimeline.topic())

      Phoenix.PubSub.broadcast(
        Atlas.PubSub,
        "control:apply",
        {:apply_start, %{job_id: "j1", regions: ["Germany"]}}
      )

      assert_receive {:timeline, %Timeline{regions: ["Germany"], status: :running}}, 1_000
      assert %Timeline{job_id: "j1"} = ApplyTimeline.current()
    end

    test "ignores service updates when no apply is running" do
      start_supervised!(Atlas.Control.ApplyTimeline)

      Phoenix.PubSub.broadcast(
        Atlas.PubSub,
        "control:service:valhalla",
        {:service_update,
         %{
           name: "valhalla",
           status: :running,
           phase: "building-tiles",
           progress: 0.5,
           ready?: false,
           last_error: nil
         }}
      )

      Process.sleep(50)
      refute ApplyTimeline.current()
    end
  end
end
