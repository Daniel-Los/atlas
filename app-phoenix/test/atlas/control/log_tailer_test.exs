defmodule Atlas.Control.LogTailerTest do
  use ExUnit.Case, async: false

  alias Atlas.Control.LogTailer

  setup do
    start_supervised!({Registry, keys: :unique, name: Atlas.Control.Registry})

    fixture =
      Path.join(System.tmp_dir!(), "tailer-fixture-#{System.unique_integer([:positive])}.log")

    File.write!(fixture, "line one\nline two\n")
    on_exit(fn -> File.rm(fixture) end)
    {:ok, fixture: fixture}
  end

  test "broadcasts each line and an EOF marker when the stream ends", %{fixture: fixture} do
    Phoenix.PubSub.subscribe(Atlas.PubSub, "logs:photon")

    start_supervised!(
      {LogTailer, name: "photon", executable: System.find_executable("cat"), args: [fixture]}
    )

    assert_receive {:log_line, "line one"}, 1_000
    assert_receive {:log_line, "line two"}, 1_000
    assert_receive {:log_eof, 0}, 1_000
  end

  test "recent/1 replays buffered lines to late-opening viewers", %{fixture: fixture} do
    Phoenix.PubSub.subscribe(Atlas.PubSub, "logs:photon")

    # Emit the fixture then stay alive, like `docker compose logs -f`.
    start_supervised!(
      {LogTailer,
       name: "photon",
       executable: System.find_executable("sh"),
       args: ["-c", "cat #{fixture}; sleep 5"]}
    )

    assert_receive {:log_line, "line two"}, 1_000

    assert LogTailer.recent("photon") == ["line one", "line two"]
  end

  test "recent/1 is empty when no tailer runs" do
    assert LogTailer.recent("ghost") == []
  end

  test "default args tail compose logs with history" do
    args = LogTailer.default_args("photon")
    assert args == ["compose", "logs", "-f", "--tail=200", "photon"]
  end

  test "default args pass the same --env-file as DockerCompose" do
    dir = Path.join(System.tmp_dir!(), "tailer-env-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    env_file = Path.join(dir, ".env")
    File.write!(env_file, "COUNTRY_CODE=nl\n")
    System.put_env("ATLAS_ENV_FILE", env_file)

    on_exit(fn ->
      System.delete_env("ATLAS_ENV_FILE")
      File.rm_rf!(dir)
    end)

    args = LogTailer.default_args("photon")

    assert Enum.chunk_every(args, 2, 1) |> Enum.member?(["--env-file", env_file]),
           "compose interpolates the whole file for every subcommand; without --env-file " <>
             "`logs` resolves variables differently from `up` and warns on each one"
  end

  test "default args resolve the compose project against HOST_PROJECT_DIR" do
    System.put_env("HOST_PROJECT_DIR", "/srv/atlas")
    on_exit(fn -> System.delete_env("HOST_PROJECT_DIR") end)

    args = LogTailer.default_args("photon")

    assert args == [
             "compose",
             "--project-directory",
             "/srv/atlas",
             "logs",
             "-f",
             "--tail=200",
             "photon"
           ]
  end
end
