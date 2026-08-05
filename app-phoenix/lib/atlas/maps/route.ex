defmodule Atlas.Maps.Route do
  @moduledoc """
  Point-to-point routing via Valhalla.

  Wraps `Atlas.Maps.Upstream.Valhalla` and normalises its response into a
  `Atlas.Maps.Result`.
  """

  alias Atlas.Maps.{Result, Upstream.Client, Upstream.Valhalla}
  require Logger

  @doc """
  Plan a route. Returns:

      {:ok, %Result{features: %{summary: %{}, legs: [...], shape_format: "valhalla_encoded_polyline6"}}}

  Or on upstream failure:

      {:error, %Client.Unavailable{} | %Client.BadResponse{}}
  """
  def plan(opts) do
    case Valhalla.route(opts) do
      {:ok, body} ->
        trip = body["trip"] || %{}

        {:ok,
         %Result{
           features: %{
             summary: trip["summary"] || %{},
             legs: trip["legs"] || [],
             shape_format: "valhalla_encoded_polyline6"
           },
           upstream_status: "ok"
         }}

      {:error, %Client.Unavailable{} = e} ->
        Logger.warning("valhalla unavailable: #{Exception.message(e)}")
        {:error, e}

      {:error, %Client.BadResponse{} = e} ->
        Logger.warning("valhalla bad response: #{Exception.message(e)}")
        {:error, e}
    end
  end
end
