defmodule Atlas.Control.ApplyTimeline do
  @moduledoc """
  One timeline for a region apply, from the first byte downloaded to the
  sidecars actually being ready to serve.

  Folds two existing event streams — `RegionApplier`'s lifecycle events and
  `ServiceState`'s per-service snapshots — into a single struct the LiveViews
  render without any merge logic of their own.

  A `Measure` with `total: nil` means the total is genuinely unknown. Callers
  must render observed facts (bytes so far, elapsed) rather than a bar;
  `percentage/1` returns `nil` for such a measure by construction.
  """

  defmodule Measure do
    @moduledoc "A progress reading. `total: nil` means indeterminate."
    defstruct [:kind, :current, :total]

    @type t :: %__MODULE__{
            kind: :bytes | :fraction | :count,
            current: number(),
            total: number() | nil
          }
  end

  defmodule Item do
    @moduledoc "One file within a stage."
    defstruct [:label, :source, :state, :measure]

    @type t :: %__MODULE__{
            label: String.t(),
            source: String.t() | nil,
            state: :pending | :running | :done | :error,
            measure: Measure.t() | nil
          }
  end

  defmodule Stage do
    @moduledoc "One step of the journey."
    defstruct [
      :key,
      :label,
      :detail,
      :measure,
      :started_at,
      :finished_at,
      :error,
      state: :pending,
      items: []
    ]

    @type t :: %__MODULE__{
            key: atom(),
            label: String.t(),
            state: :pending | :running | :done | :skipped | :error,
            items: [Item.t()]
          }
  end

  defmodule Timeline do
    @moduledoc "The whole journey for one apply job."
    defstruct [
      :job_id,
      :started_at,
      :finished_at,
      regions: [],
      status: :running,
      current_step: 1,
      stages: []
    ]
  end

  @applier_stages [
    {:download, "Download region data"},
    {:merge, "Merge into current.osm.pbf"},
    {:stage_otp, "Stage transit inputs"},
    {:convert, "Convert for Overpass"}
  ]

  @phase_stage %{
    downloading: :download,
    merging: :merge,
    staging: :stage_otp,
    converting: :convert
  }

  # Sidecars a region apply can restart (mirrors RegionApplier's
  # `@ingest_services`). A compile-time literal map — not
  # `String.to_existing_atom/1` — turns the broadcast's string name into a
  # stage key. `to_existing_atom/1` only succeeds once something has called
  # `String.to_atom/1` on that exact string at runtime; in production that
  # happens solely via `service_stage/1` inside `start/3`, for whichever
  # services *this* job restarts. A `:service_update` for a known service
  # this BEAM has genuinely never restarted (fresh boot, e.g. "overpass"
  # broadcasting before any apply job's `services` list ever included it)
  # would hit an atom that was never created and raise `ArgumentError`. The
  # atoms below are literals in this module's own source, so they exist the
  # moment this module is loaded — independent of what `start/3` has or
  # hasn't been called with. `Map.fetch/2` then can only ever hit or miss,
  # never raise.
  @service_atoms %{"valhalla" => :valhalla, "overpass" => :overpass, "otp" => :otp}

  @doc """
  Build the initial timeline. `services` are the sidecars this job will
  restart; only those get a row (see the attribution rule in the spec).
  """
  def start(regions, services, now) do
    %Timeline{
      regions: regions,
      started_at: now,
      status: :running,
      current_step: 1,
      stages: Enum.map(@applier_stages, &stage/1) ++ Enum.map(services, &service_stage/1)
    }
  end

  @doc "Percentage for a measure, or nil when the total is unknown."
  def percentage(%Measure{total: total}) when is_nil(total), do: nil
  def percentage(%Measure{total: total}) when total <= 0, do: nil
  def percentage(%Measure{current: current, total: total}), do: round(current / total * 100)
  def percentage(nil), do: nil

  @doc "Fold one event into the timeline."
  def apply_event(timeline, {:apply_progress, %{phase: :downloading} = payload}, now) do
    timeline
    |> put_stage(:download, fn stage ->
      stage
      |> mark_running(now)
      |> put_item(payload[:item])
    end)
    |> recompute_step()
  end

  def apply_event(timeline, {:apply_progress, %{phase: phase}}, now)
      when is_map_key(@phase_stage, phase) do
    key = Map.fetch!(@phase_stage, phase)

    timeline
    |> complete_stages_before(key, now)
    |> put_stage(key, &mark_running(&1, now))
    |> recompute_step()
  end

  # `restarting` is the applier handing off to the sidecars: its own work is
  # done, and the service stages take over from here.
  def apply_event(timeline, {:apply_progress, %{phase: :restarting}}, now) do
    timeline
    |> complete_applier_stages(now)
    |> recompute_step()
  end

  def apply_event(timeline, {:apply_done, _payload}, now) do
    %{
      timeline
      | status: :done,
        finished_at: now,
        stages: Enum.map(timeline.stages, &finish_stage(&1, now))
    }
  end

  def apply_event(timeline, {:apply_error, %{phase: phase} = payload}, now) do
    key = Map.get(@phase_stage, phase, :convert)

    timeline
    |> complete_stages_before(key, now)
    |> put_stage(key, fn stage ->
      %{stage | state: :error, error: to_message(payload[:reason]), finished_at: now}
    end)
    |> skip_pending(now)
    |> Map.put(:status, :error)
    |> Map.put(:finished_at, now)
  end

  def apply_event(timeline, {:service_update, %{name: name} = snapshot}, now) do
    case Map.fetch(@service_atoms, name) do
      {:ok, key} -> adopt_service(timeline, key, snapshot, now)
      :error -> timeline
    end
  end

  def apply_event(timeline, _event, _now), do: timeline

  defp adopt_service(timeline, key, snapshot, now) do
    if Enum.any?(timeline.stages, &(&1.key == key)) do
      timeline
      |> put_stage(key, &fold_service(&1, snapshot, now))
      |> recompute_step()
    else
      timeline
    end
  end

  defp fold_service(stage, %{status: :error} = snapshot, now) do
    %{stage | state: :error, error: to_message(snapshot[:last_error]), finished_at: now}
  end

  defp fold_service(stage, %{ready?: true}, now) do
    %{stage | state: :done, detail: "ready", finished_at: now, measure: nil}
  end

  defp fold_service(stage, snapshot, now) do
    %{
      stage
      | state: :running,
        started_at: stage.started_at || now,
        detail: snapshot[:phase],
        measure: service_measure(snapshot[:progress])
    }
  end

  defp service_measure(progress) when is_number(progress),
    do: %Measure{kind: :fraction, current: progress, total: 1}

  defp service_measure(_progress), do: nil

  defp stage({key, label}), do: %Stage{key: key, label: label}

  defp service_stage(name),
    do: %Stage{key: String.to_atom(name), label: String.capitalize(name)}

  defp put_stage(%Timeline{stages: stages} = timeline, key, fun) do
    %{timeline | stages: Enum.map(stages, fn s -> if s.key == key, do: fun.(s), else: s end)}
  end

  defp mark_running(%Stage{state: :pending} = stage, now),
    do: %{stage | state: :running, started_at: now}

  defp mark_running(stage, _now), do: stage

  defp put_item(stage, nil), do: stage

  defp put_item(%Stage{items: items} = stage, %{label: label} = raw) do
    item = %Item{
      label: label,
      source: raw[:source],
      state: :running,
      measure: %Measure{kind: :bytes, current: raw[:current] || 0, total: raw[:total]}
    }

    %{stage | items: merge_item(items, item)}
  end

  # A new label means the previous file finished: the applier downloads
  # sequentially, so anything still "running" when a new one starts is done.
  defp merge_item(items, %Item{label: label} = item) do
    if Enum.any?(items, &(&1.label == label)) do
      replace_item(items, item)
    else
      Enum.map(items, &finish_item/1) ++ [item]
    end
  end

  defp replace_item(items, %Item{label: label} = item) do
    Enum.map(items, &if(&1.label == label, do: item, else: &1))
  end

  defp finish_item(%Item{state: :running} = item), do: %{item | state: :done}
  defp finish_item(item), do: item

  defp recompute_step(%Timeline{stages: stages} = timeline) do
    index = Enum.find_index(stages, &(&1.state in [:running, :pending])) || length(stages) - 1
    %{timeline | current_step: index + 1}
  end

  defp applier_keys, do: Enum.map(@applier_stages, fn {key, _label} -> key end)

  defp complete_stages_before(timeline, key, now) do
    keys = applier_keys()
    cutoff = Enum.find_index(keys, &(&1 == key)) || 0
    earlier = Enum.take(keys, cutoff)

    Enum.reduce(earlier, timeline, fn k, acc ->
      put_stage(acc, k, &finish_stage(&1, now))
    end)
  end

  defp complete_applier_stages(timeline, now) do
    Enum.reduce(applier_keys(), timeline, fn k, acc ->
      put_stage(acc, k, &finish_stage(&1, now))
    end)
  end

  defp finish_stage(%Stage{state: state} = stage, _now) when state in [:error, :skipped],
    do: stage

  defp finish_stage(%Stage{finished_at: nil} = stage, now),
    do: %{stage | state: :done, finished_at: now, items: Enum.map(stage.items, &finish_item/1)}

  defp finish_stage(stage, _now), do: %{stage | state: :done}

  defp skip_pending(%Timeline{stages: stages} = timeline, _now) do
    %{
      timeline
      | stages:
          Enum.map(stages, fn
            %Stage{state: :pending} = s -> %{s | state: :skipped}
            s -> s
          end)
    }
  end

  defp to_message(reason) when is_binary(reason), do: reason
  defp to_message(reason), do: inspect(reason)
end
