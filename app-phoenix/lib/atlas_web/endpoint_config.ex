defmodule AtlasWeb.EndpointConfig do
  @moduledoc """
  Resolves the externally-visible endpoint settings from the environment.

  Atlas is deployed three ways, and they disagree about scheme and port:

    * behind a TLS-terminating proxy — `https` on 443 (the default)
    * directly on a LAN host — `http` on a non-standard port such as 8484
    * on localhost for a quick look

  Pure functions over an env map so each combination is testable without
  booting an endpoint. `config/runtime.exs` feeds them `System.get_env/0`.
  """

  @default_host "example.com"
  @default_scheme "https"
  @falsey ~w(false 0 no off)

  @doc "Endpoint `:url` config — the host/port/scheme Atlas advertises."
  def url(env) do
    scheme = scheme(env)
    [host: host(env), port: port(env, scheme), scheme: scheme]
  end

  @doc "Public hostname clients reach Atlas on."
  def host(env), do: presence(env["PHX_HOST"]) || @default_host

  @doc """
  Public scheme — `https` unless explicitly set to `http`.

  A misspelling raises rather than falling back to `https`: silently keeping
  the redirect on is exactly the failure the operator was trying to escape.
  """
  def scheme(env) do
    case presence(env["PHX_SCHEME"]) do
      nil ->
        @default_scheme

      value ->
        case String.downcase(value) do
          "http" ->
            "http"

          "https" ->
            "https"

          other ->
            raise ArgumentError,
                  "PHX_SCHEME must be \"http\" or \"https\", got: #{inspect(other)}"
        end
    end
  end

  @doc "Public port. Defaults to the scheme's standard port."
  def port(env, scheme \\ nil) do
    scheme = scheme || scheme(env)

    case presence(env["PHX_PORT"]) do
      nil -> if scheme == "http", do: 80, else: 443
      value -> parse_port(value)
    end
  end

  defp parse_port(value) do
    case Integer.parse(value) do
      {port, ""} when port in 1..65_535 ->
        port

      _ ->
        raise ArgumentError,
              "PHX_PORT must be an integer between 1 and 65535, got: #{inspect(value)}"
    end
  end

  @doc """
  Whether to redirect plain HTTP to HTTPS.

  Defaults to `true`, but follows `PHX_SCHEME=http` down to `false` — asking
  to be served over http and then being redirected to https is never what the
  operator meant. An explicit `FORCE_SSL` always wins.
  """
  def force_ssl?(env) do
    case presence(env["FORCE_SSL"]) do
      nil -> scheme(env) != "http"
      value -> String.downcase(value) not in @falsey
    end
  end

  @doc """
  LiveView origin policy: `true` (validate against `url/1`), `false`, or an
  explicit allow list from a comma-separated `PHX_CHECK_ORIGIN`.
  """
  def check_origin(env) do
    case presence(env["PHX_CHECK_ORIGIN"]) do
      nil ->
        true

      value ->
        if String.downcase(value) in @falsey do
          false
        else
          value
          |> String.split(",")
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))
        end
    end
  end

  @doc """
  Runtime gate for `Plug.SSL`, wired through `force_ssl: [exclude: [conn: …]]`.

  Phoenix reads `:force_ssl` with `Application.compile_env/2`, so the plug is
  baked into the endpoint at build time and `FORCE_SSL=false` cannot remove
  it. `:exclude`'s `conn:` callback *is* evaluated per request, so the runtime
  setting is applied here instead.
  """
  def skip_https_redirect?(_conn), do: not Application.get_env(:atlas, :force_ssl, true)

  defp presence(nil), do: nil
  defp presence(""), do: nil
  defp presence(value) when is_binary(value), do: String.trim(value) |> nil_if_empty()

  defp nil_if_empty(""), do: nil
  defp nil_if_empty(value), do: value
end
