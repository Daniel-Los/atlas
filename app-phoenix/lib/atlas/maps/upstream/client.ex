defmodule Atlas.Maps.Upstream.Client do
  @moduledoc """
  Shared HTTP client for every upstream map service.

  Builds preconfigured `Req` clients — from explicit options or from
  `<PREFIX>_URL` / `<PREFIX>_TIMEOUT` / `<PREFIX>_OPEN_TIMEOUT` env vars — and
  normalises failures into two exceptions the contexts can match on:
  `Unavailable` (could not connect) and `BadResponse` (connected, bad status).
  """

  require Logger

  defmodule Unavailable do
    defexception [:message, :upstream]
  end

  defmodule BadResponse do
    @moduledoc """
    An upstream answered, but with a non-2xx status.

    `:body` carries the decoded response so callers can surface the upstream's
    own explanation. Valhalla, for one, returns a specific `error_code` and
    message on 400; without the body the caller can only invent a reason.
    """

    defexception [:message, :upstream, :status, :body]
  end

  def build(base_url, opts \\ []) do
    Req.new(
      base_url: base_url,
      connect_options: [
        timeout: Keyword.get(opts, :open_timeout, 2_000),
        protocols: [:http1]
      ],
      receive_timeout: Keyword.get(opts, :timeout, 5_000),
      retry: &retry_only_pool/2,
      max_retries: 2,
      retry_delay: 10,
      decode_json: [keys: :strings]
    )
  end

  @doc """
  Build a client from `<PREFIX>_URL` / `<PREFIX>_TIMEOUT` / `<PREFIX>_OPEN_TIMEOUT`
  env vars. `default_url` is used when `<PREFIX>_URL` is unset.

      Client.build_from_env("PHOTON", "http://localhost:8001",
                            timeout: 5_000, open_timeout: 2_000)
  """
  def build_from_env(prefix, default_url, defaults \\ []) do
    base_url = System.get_env("#{prefix}_URL") || default_url
    timeout = env_int("#{prefix}_TIMEOUT", Keyword.get(defaults, :timeout, 5_000))
    open_timeout = env_int("#{prefix}_OPEN_TIMEOUT", Keyword.get(defaults, :open_timeout, 2_000))
    build(base_url, timeout: timeout, open_timeout: open_timeout)
  end

  @doc "Read an integer env var, falling back to `default` when unset."
  def env_int(key, default) do
    case System.get_env(key) do
      nil -> default
      "" -> default
      val -> parse_int(key, val, default)
    end
  end

  # Falls back rather than raising: compose renders `${VAR:-}` as an empty
  # string for every declared-but-unset knob, and a typo in one of them used to
  # take down every request that read it — a 500 on the whole API because a
  # timeout was spelled "10s".
  defp parse_int(key, val, default) do
    case Integer.parse(val) do
      {int, ""} ->
        int

      _ ->
        Logger.warning("#{key}=#{inspect(val)} is not an integer, using #{default}")
        default
    end
  end

  # Retry only on Finch pool exhaustion. All other errors (connect refused,
  # 5xx, etc.) fail fast so Bypass-down tests stay quick.
  defp retry_only_pool(_req, %Req.HTTPError{reason: :pool_not_available}), do: true
  defp retry_only_pool(_req, _other), do: false

  def get(req, path, params \\ []) do
    case Req.get(req, url: path, params: params) do
      {:ok, %{status: s, body: body}} when s in 200..299 ->
        {:ok, maybe_decode(body)}

      {:ok, %{status: s, body: response_body}} ->
        {:error,
         %BadResponse{
           message: "#{s} from #{req.options[:base_url]}#{path}",
           status: s,
           body: maybe_decode(response_body)
         }}

      {:error, exception} ->
        {:error, %Unavailable{message: Exception.message(exception)}}
    end
  end

  def post(req, path, body) do
    case Req.post(req, url: path, json: body) do
      {:ok, %{status: s, body: response_body}} when s in 200..299 ->
        {:ok, maybe_decode(response_body)}

      {:ok, %{status: s, body: response_body}} ->
        {:error,
         %BadResponse{
           message: "#{s} from #{req.options[:base_url]}#{path}",
           status: s,
           body: maybe_decode(response_body)
         }}

      {:error, exception} ->
        {:error, %Unavailable{message: Exception.message(exception)}}
    end
  end

  def post_raw(req, path, body, content_type \\ "text/plain") do
    case Req.post(req, url: path, body: body, headers: [{"content-type", content_type}]) do
      {:ok, %{status: s, body: response_body}} when s in 200..299 ->
        {:ok, maybe_decode(response_body)}

      {:ok, %{status: s, body: response_body}} ->
        {:error,
         %BadResponse{
           message: "#{s} from #{req.options[:base_url]}#{path}",
           status: s,
           body: maybe_decode(response_body)
         }}

      {:error, exception} ->
        {:error, %Unavailable{message: Exception.message(exception)}}
    end
  end

  defp maybe_decode(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> decoded
      {:error, _} -> body
    end
  end

  defp maybe_decode(body), do: body
end
