defmodule Atlas.Maps.MapMatch do
  @moduledoc """
  Snap a recorded GPS trace onto the road network via Valhalla's Meili
  matcher (`/trace_route`).

  This is the inverse of `Atlas.Maps.Route`: routing invents a path between
  two points, matching takes a path you already walked and decides which edges
  you were actually on.

  Two output shapes, chosen with `:format`:

    * `"polyline6"` (default) — Valhalla's legs verbatim, each carrying an
      encoded `shape`. Matches what `/api/v1/route` returns.
    * `"geojson"` — legs decoded and stitched into one `LineString`, so
      callers need no polyline decoder of their own.
  """

  alias Atlas.Geometry.Polyline
  alias Atlas.Maps.{Result, Upstream.Client, Upstream.Valhalla}

  require Logger

  @min_points 2
  @max_points 10_000
  @polyline_precision 6

  # Only used when Valhalla's own explanation is missing or unreadable.
  @generic_rejection "the trace could not be matched to the road network — it may lie " <>
                       "outside the loaded region, or the points may be too sparse or too noisy"

  @doc """
  Upper bound on trace length, overridable with `MAP_MATCH_MAX_POINTS`.

  Matching is superlinear in point count and holds a Valhalla worker for the
  whole request, so an unbounded trace is a denial-of-service on a shared
  instance.
  """
  def max_points, do: Client.env_int("MAP_MATCH_MAX_POINTS", @max_points)

  @doc "Smallest trace that can be matched."
  def min_points, do: @min_points

  @doc """
  Match `:shape` — a list of `%{lat:, lon:}` maps, optionally with `:time`
  and `:accuracy` — onto the road network.

  Returns `{:ok, %Result{}}`, or one of the error tuples
  `AtlasWeb.Api.V1.FallbackController` knows how to render.
  """
  def match(opts) do
    shape = opts[:shape] || []

    with :ok <- validate_shape(shape),
         {:ok, body} <- request(shape, opts) do
      {:ok, build_result(body, opts[:format])}
    end
  end

  defp validate_shape(shape) do
    count = length(shape)
    max = max_points()

    cond do
      count < @min_points ->
        {:error, :invalid, "shape must have at least #{@min_points} points",
         %{param: "shape", min: @min_points}}

      count > max ->
        {:error, :too_many, max}

      true ->
        :ok
    end
  end

  defp request(shape, opts) do
    Valhalla.trace_route(
      shape: shape,
      mode: opts[:mode] || "auto",
      shape_match: opts[:shape_match],
      trace_options: opts[:trace_options]
    )
    |> handle_response()
  end

  # Every Valhalla 400 is the caller's input being unusable, so 422 is right
  # across the board — 502 would send the operator debugging a service that is
  # behaving correctly. But the REASON varies: unmatchable geometry
  # (error_code 171), a trace longer than `max_distance` (200 km by default —
  # one day of driving), more points than `max_shape`, an out-of-range trace
  # option. Relay Valhalla's own message instead of asserting one of them.
  defp handle_response({:ok, body}), do: {:ok, body}

  defp handle_response({:error, %Client.BadResponse{status: 400, body: body}}) do
    Logger.warning("valhalla rejected the trace: #{inspect(body)}")
    {:error, :invalid, upstream_message(body), upstream_details(body)}
  end

  defp handle_response({:error, %Client.Unavailable{} = error}) do
    Logger.warning("valhalla unavailable: #{Exception.message(error)}")
    {:error, error}
  end

  defp handle_response({:error, %Client.BadResponse{} = error}) do
    Logger.warning("valhalla bad response: #{Exception.message(error)}")
    {:error, error}
  end

  defp upstream_message(%{"error" => error}) when is_binary(error) and error != "", do: error
  defp upstream_message(_body), do: @generic_rejection

  defp upstream_details(%{"error_code" => code}) when is_integer(code),
    do: %{param: "shape", upstream_error_code: code}

  defp upstream_details(_body), do: %{param: "shape"}

  defp build_result(body, "geojson") do
    trip = body["trip"] || %{}

    %Result{
      features: %{
        summary: trip["summary"] || %{},
        geometry: %{type: "LineString", coordinates: coordinates(trip["legs"] || [])},
        shape_format: "geojson"
      },
      upstream_status: "ok"
    }
  end

  defp build_result(body, _format) do
    trip = body["trip"] || %{}

    %Result{
      features: %{
        summary: trip["summary"] || %{},
        legs: trip["legs"] || [],
        shape_format: "valhalla_encoded_polyline6"
      },
      upstream_status: "ok"
    }
  end

  # Valhalla repeats the boundary vertex at the end of one leg and the start of
  # the next, so a flat concatenation emits it twice. `Enum.dedup/1` drops only
  # consecutive repeats, which is exactly the seam and never a genuine
  # stationary stretch elsewhere in the trace.
  defp coordinates(legs) do
    legs
    |> Enum.flat_map(&Polyline.decode(&1["shape"] || "", @polyline_precision))
    |> Enum.dedup()
    |> Enum.map(fn {lat, lon} -> [lon, lat] end)
  end
end
