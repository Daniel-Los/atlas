defmodule Atlas.Control.Osmium do
  @moduledoc """
  Wraps native `osmium-tool` invocations through a single GenServer so two
  merges never run concurrently against the same data dir.

  The binary is installed in the release image; all paths are container-local
  (no docker-run indirection, no host-path translation).

  Production passes a `System.cmd/3`-shaped runner; tests inject a stub.
  """

  use GenServer

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Merge `sources` (paths relative to `data_dir`) into `out` (also relative).

  Equivalent to running `osmium merge <sources...> -O -o <out>` from `data_dir`.
  Returns `{:ok, output}` or `{:error, exit_code, output}`.
  """
  def merge(data_dir, sources, out) when is_list(sources) do
    args = ["merge"] ++ sources ++ ["-O", "-o", out]
    GenServer.call(__MODULE__, {:osmium, data_dir, args}, call_timeout())
  end

  @doc """
  Convert a PBF file to OSM-XML+bzip2 (required by overpass-api).
  Both paths are relative to `data_dir`.
  """
  def convert_to_osm_bz2(data_dir, in_path, out_path) do
    args = ["cat", in_path, "-o", out_path, "-O", "-f", "osm.bz2"]
    GenServer.call(__MODULE__, {:osmium, data_dir, args}, call_timeout())
  end

  @doc """
  Client-side ceiling for an osmium invocation. Defaults to `:infinity`.

  These are long-running external ports: bzip2 compression is effectively
  single-threaded, so a country-scale `osmium cat -f osm.bz2` runs well past
  an hour. A wall-clock ceiling kills it mid-write and strands a `.partial`,
  so serialization — not a deadline — is what this GenServer is for.
  """
  def call_timeout, do: Application.get_env(:atlas, :osmium_timeout, :infinity)

  @impl true
  def init(opts) do
    {:ok,
     %{
       runner: Keyword.get(opts, :runner, &default_runner/3),
       stall_timeout: Keyword.get(opts, :stall_timeout, stall_timeout()),
       stall_poll: Keyword.get(opts, :stall_poll, :timer.seconds(30))
     }}
  end

  @impl true
  def handle_call({:osmium, data_dir, args}, _from, state) do
    task =
      Task.async(fn ->
        state.runner.("osmium", args, cd: data_dir, stderr_to_stdout: true)
      end)

    reply =
      case await_with_watchdog(task, output_path(data_dir, args), state) do
        {:ok, {output, 0}} -> {:ok, output}
        {:ok, {output, code}} -> {:error, code, output}
        {:error, :stalled, detail} -> {:error, :stalled, detail}
      end

    {:reply, reply, state}
  end

  # osmium writes its output file steadily, so "the file stopped growing" is a
  # far better death signal than a wall-clock deadline: a legitimately slow
  # convert keeps growing for hours, while a wedged one flatlines immediately.
  defp await_with_watchdog(task, out_path, state) do
    do_await(task, out_path, state, size_of(out_path), 0)
  end

  defp do_await(task, out_path, state, last_size, stalled_for) do
    case Task.yield(task, state.stall_poll) do
      {:ok, result} ->
        {:ok, result}

      nil ->
        size = size_of(out_path)

        cond do
          size > last_size ->
            do_await(task, out_path, state, size, 0)

          stalled_for + state.stall_poll >= state.stall_timeout ->
            Task.shutdown(task, :brutal_kill)

            {:error, :stalled,
             "no progress on #{out_path} for #{div(state.stall_timeout, 1000)}s — killed"}

          true ->
            do_await(task, out_path, state, size, stalled_for + state.stall_poll)
        end
    end
  end

  defp size_of(nil), do: 0

  defp size_of(path) do
    case File.stat(path) do
      {:ok, %File.Stat{size: size}} -> size
      {:error, _} -> 0
    end
  end

  # Both `merge` and `cat` name their destination right after `-o`.
  defp output_path(data_dir, args) do
    case Enum.drop_while(args, &(&1 != "-o")) do
      ["-o", out | _] -> Path.expand(out, data_dir)
      _ -> nil
    end
  end

  @doc """
  How long the output file may stop growing before the invocation is killed.
  Defaults to 30 minutes; override with `:osmium_stall_timeout`.
  """
  def stall_timeout,
    do: Application.get_env(:atlas, :osmium_stall_timeout, :timer.minutes(30))

  defp default_runner(cmd, args, opts), do: System.cmd(cmd, args, opts)
end
