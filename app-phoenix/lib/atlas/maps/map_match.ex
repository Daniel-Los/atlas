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

  # Valhalla answers 400 when no road network candidate fits the trace
  # (error_code 171, "No suitable edges near location"). That is unmatchable
  # input, not a sick upstream — surfacing it as 502 sends the operator
  # debugging a service that is behaving correctly.
  defp handle_response({:ok, body}), do: {:ok, body}

  defp handle_response({:error, %Client.BadResponse{status: 400}}) do
    {:error, :invalid,
     "the trace could not be matched to the road network — it may lie outside " <>
       "the loaded region, or the points may be too sparse or too noisy", %{param: "shape"}}
  end

  defp handle_response({:error, %Client.Unavailable{} = error}) do
    Logger.warning("valhalla unavailable: #{Exception.message(error)}")
    {:error, error}
  end

  defp handle_response({:error, %Client.BadResponse{} = error}) do
    Logger.warning("valhalla bad response: #{Exception.message(error)}")
    {:error, error}
  end

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
