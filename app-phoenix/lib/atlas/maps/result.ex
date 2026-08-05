defmodule Atlas.Maps.Result do
  @moduledoc """
  A GeoJSON-shaped result envelope returned by every `Atlas.Maps` lookup.

  Carries the `features` list plus `upstream_status`, which lets a partially
  degraded answer (one upstream down, the rest fine) still reach the client.
  """

  defstruct features: [], upstream_status: "ok"

  @type upstream_status :: String.t()
  @type t :: %__MODULE__{features: term(), upstream_status: upstream_status}
end
