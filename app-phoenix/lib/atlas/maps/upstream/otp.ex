defmodule Atlas.Maps.Upstream.Otp do
  alias Atlas.Maps.Upstream.Client

  @default_modes "TRANSIT,WALK"
  @direct_modes ~w(WALK BICYCLE CAR)
  @transit_modes ~w(AIRPLANE BUS CABLE_CAR COACH FERRY FUNICULAR GONDOLA MONORAIL RAIL SUBWAY TRAM TROLLEYBUS)

  def default_modes, do: @default_modes

  def default do
    Client.build_from_env("OTP", "http://localhost:8080", timeout: 15_000, open_timeout: 2_000)
  end

  def plan(req \\ default(), opts) do
    opts = Map.new(opts)
    %{from: from, to: to} = opts
    num = opts[:num] || 3

    body = %{
      query: plan_query(),
      variables: %{
        origin: location_input(from),
        destination: location_input(to),
        dateTime: date_time_input(opts),
        modes: modes_input(opts[:modes] || @default_modes)
      }
    }

    case Client.post(req, "/otp/gtfs/v1", body) do
      {:ok, %{"errors" => errors}} ->
        {:error, %Client.BadResponse{message: "OTP plan error: #{graphql_error(errors)}"}}

      {:ok, body} ->
        {:ok, normalize_plan(body, num)}

      error ->
        error
    end
  end

  defp location_input(coord) do
    %{
      location: %{
        coordinate: %{
          latitude: coord[:lat],
          longitude: coord[:lon]
        }
      }
    }
  end

  defp date_time_input(opts) do
    key = if truthy?(opts[:arrive_by]), do: :latestArrival, else: :earliestDeparture
    %{key => date_time(opts)}
  end

  defp date_time(%{datetime: datetime}) when is_binary(datetime), do: datetime
  defp date_time(%{date_time: datetime}) when is_binary(datetime), do: datetime

  defp date_time(%{date: date, time: time}) when is_binary(date) and is_binary(time) do
    ensure_timezone("#{date}T#{time}")
  end

  defp date_time(_opts), do: DateTime.utc_now() |> DateTime.to_iso8601()

  defp ensure_timezone(datetime) do
    if String.match?(datetime, ~r/(Z|[+-]\d{2}:?\d{2})$/), do: datetime, else: datetime <> "Z"
  end

  defp truthy?(value) when value in [true, "true", "1", 1, "yes"], do: true
  defp truthy?(_), do: false

  defp modes_input(modes) do
    requested = modes |> to_string() |> String.split(",", trim: true) |> Enum.map(&upcase_trim/1)
    requested = if requested == [], do: ["TRANSIT", "WALK"], else: requested
    transit = requested |> Enum.flat_map(&expand_transit_mode/1) |> Enum.uniq()

    %{}
    |> put_if_present(:direct, Enum.filter(requested, &(&1 in @direct_modes)))
    |> put_transit_modes(transit)
  end

  defp upcase_trim(mode), do: mode |> String.trim() |> String.upcase()

  defp expand_transit_mode("TRANSIT"), do: @transit_modes
  defp expand_transit_mode(mode) when mode in @transit_modes, do: [mode]
  defp expand_transit_mode(_), do: []

  defp put_if_present(map, _key, []), do: map
  defp put_if_present(map, key, value), do: Map.put(map, key, value)

  defp put_transit_modes(map, []), do: map

  defp put_transit_modes(map, modes) do
    Map.put(map, :transit, %{transit: Enum.map(modes, &%{mode: &1})})
  end

  defp normalize_plan(body, num) do
    itineraries =
      body
      |> get_in(["data", "planConnection", "edges"])
      |> List.wrap()
      |> Enum.map(fn edge -> edge["node"] || edge["itinerary"] || %{} end)
      |> Enum.take(num)
      |> Enum.map(&normalize_itinerary/1)

    %{"plan" => %{"from" => nil, "to" => nil, "itineraries" => itineraries}}
  end

  defp normalize_itinerary(itinerary) do
    %{
      "startTime" => itinerary["startTime"] || itinerary["start"],
      "endTime" => itinerary["endTime"] || itinerary["end"],
      "duration" => itinerary["duration"],
      "walkDistance" => itinerary["walkDistance"],
      "transfers" => itinerary["numberOfTransfers"],
      "legs" => itinerary |> Map.get("legs", []) |> Enum.map(&normalize_leg/1)
    }
  end

  defp normalize_leg(leg) do
    route = leg["route"] || %{}
    agency = leg["agency"] || %{}

    %{
      "mode" => leg["mode"],
      "routeShortName" => route["shortName"],
      "route" => route["longName"],
      "headsign" => leg["headsign"],
      "agencyName" => agency["name"],
      "startTime" => leg["startTime"] || leg["start"],
      "endTime" => leg["endTime"] || leg["end"],
      "duration" => leg["duration"],
      "distance" => leg["distance"],
      "from" => leg["from"],
      "to" => leg["to"],
      "legGeometry" => leg["legGeometry"]
    }
  end

  defp graphql_error(errors) when is_list(errors) do
    Enum.map_join(errors, "; ", fn error -> error["message"] || inspect(error) end)
  end

  defp graphql_error(error), do: inspect(error)

  defp plan_query do
    """
    query PlanConnection($origin: PlanLabeledLocationInput!, $destination: PlanLabeledLocationInput!, $dateTime: PlanDateTimeInput!, $modes: PlanModesInput) {
      planConnection(origin: $origin, destination: $destination, dateTime: $dateTime, modes: $modes) {
        edges {
          node {
            start
            end
            startTime
            endTime
            duration
            walkDistance
            numberOfTransfers
            legs {
              mode
              headsign
              startTime
              endTime
              duration
              distance
              from { name lat lon }
              to { name lat lon }
              route { shortName longName }
              agency { name }
              legGeometry { points }
            }
          }
        }
      }
    }
    """
  end
end
