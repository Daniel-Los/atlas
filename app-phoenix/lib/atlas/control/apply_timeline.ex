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

  def apply_event(timeline, _event, _now), do: timeline

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
end
