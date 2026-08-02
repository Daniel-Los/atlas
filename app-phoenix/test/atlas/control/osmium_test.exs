defmodule Atlas.Control.OsmiumTest do
  use ExUnit.Case, async: false
  alias Atlas.Control.Osmium

  defp start_osmium(result) do
    test_pid = self()

    runner = fn cmd, args, opts ->
      send(test_pid, {:stub, cmd, args, opts})
      result
    end

    start_supervised!({Osmium, runner: runner})
  end

  test "merge/3 invokes native osmium merge inside data_dir" do
    start_osmium({"ok", 0})

    assert {:ok, "ok"} =
             Osmium.merge("/work/data/osm/sources", ["a.osm.pbf", "b.osm.pbf"], "../merged.osm.pbf")

    assert_received {:stub, "osmium", args, opts}

    assert args == ["merge", "a.osm.pbf", "b.osm.pbf", "-O", "-o", "../merged.osm.pbf"]
    assert opts[:cd] == "/work/data/osm/sources"
    assert opts[:stderr_to_stdout] == true
  end

  test "convert_to_osm_bz2/3 invokes native osmium cat with osm.bz2 format" do
    start_osmium({"ok", 0})

    assert {:ok, "ok"} = Osmium.convert_to_osm_bz2("/work/data/osm", "in.osm.pbf", "out.osm.bz2")

    assert_received {:stub, "osmium", args, opts}

    assert args == ["cat", "in.osm.pbf", "-o", "out.osm.bz2", "-O", "-f", "osm.bz2"]
    assert opts[:cd] == "/work/data/osm"
  end

  test "non-zero exit returns error with code and output" do
    start_osmium({"Open failed for 'a.osm.pbf'", 1})

    assert {:error, 1, "Open failed for 'a.osm.pbf'"} =
             Osmium.merge("/work/data/osm/sources", ["a.osm.pbf"], "out.osm.pbf")
  end

  describe "call timeout" do
    test "defaults to :infinity so a slow convert is never killed by wall clock" do
      assert Osmium.call_timeout() == :infinity
    end

    test "a convert far longer than the old 30-minute ceiling still succeeds" do
      # bzip2 compression of a country-scale PBF runs 45-50 min; the previous
      # hard-coded :timer.minutes(30) killed it mid-write.
      slow_runner = fn _cmd, _args, _opts ->
        Process.sleep(120)
        {"done", 0}
      end

      start_supervised!({Osmium, runner: slow_runner})

      assert {:ok, "done"} =
               Osmium.convert_to_osm_bz2("/work/data/osm", "current.osm.pbf", "out.partial")
    end

    test "a stalled convert is killed even though the call timeout is :infinity" do
      # :infinity is right for a SLOW convert (bzip2 on a planet extract runs
      # for hours). A HUNG one is different: without a stall check the GenServer
      # is wedged forever and every later apply gets {:error, :busy}.
      tmp = Path.join(System.tmp_dir!(), "osmium-stall-#{System.unique_integer([:positive])}")
      File.mkdir_p!(tmp)
      on_exit(fn -> File.rm_rf!(tmp) end)

      hung_runner = fn _cmd, _args, _opts ->
        Process.sleep(5_000)
        {"never gets here", 0}
      end

      start_supervised!({Osmium, runner: hung_runner, stall_timeout: 150, stall_poll: 30})

      assert {:error, :stalled, msg} =
               Osmium.convert_to_osm_bz2(tmp, "current.osm.pbf", "out.partial")

      assert msg =~ "no progress"
    end

    test "a slow but progressing convert is not killed by the stall watchdog" do
      tmp = Path.join(System.tmp_dir!(), "osmium-slow-#{System.unique_integer([:positive])}")
      File.mkdir_p!(tmp)
      on_exit(fn -> File.rm_rf!(tmp) end)

      out = Path.join(tmp, "out.partial")

      growing_runner = fn _cmd, _args, _opts ->
        Enum.each(1..6, fn n ->
          File.write!(out, String.duplicate("x", n * 1000))
          Process.sleep(50)
        end)

        {"done", 0}
      end

      start_supervised!({Osmium, runner: growing_runner, stall_timeout: 150, stall_poll: 30})

      assert {:ok, "done"} = Osmium.convert_to_osm_bz2(tmp, "current.osm.pbf", "out.partial")
    end

    test "the stall watchdog kills the real OS process, not just the Elixir task" do
      # Task.shutdown/2 tears down the wrapper only; the port's child survives.
      # If osmium outlives the "killed" reply it keeps writing to the data dir
      # while the freed GenServer lets the next apply start a second one.
      tmp = Path.join(System.tmp_dir!(), "osmium-kill-#{System.unique_integer([:positive])}")
      File.mkdir_p!(tmp)
      on_exit(fn -> File.rm_rf!(tmp) end)

      # The duration IS the marker: it lands in the child's own argv, so pgrep
      # can see it. A trailing comment would not — `exec` replaces the shell and
      # the comment never reaches argv, which makes the pgrep assertion pass
      # whether or not the child was actually killed.
      marker = 4000 + rem(System.unique_integer([:positive]), 900)

      # The real port-spawning runner, just pointed at `sleep` so the test does
      # not need osmium installed.
      port_runner = fn _cmd, _args, opts ->
        Osmium.spawn_and_collect("sleep", ["#{marker}"], opts)
      end

      start_supervised!({Osmium, runner: port_runner, stall_timeout: 150, stall_poll: 30})

      assert {:error, :stalled, _} =
               Osmium.convert_to_osm_bz2(tmp, "current.osm.pbf", "out.partial")

      Process.sleep(300)

      {out, _} = System.cmd("sh", ["-c", "pgrep -f 'sleep #{marker}' | wc -l"])

      assert String.trim(out) == "0",
             "the child must be dead once we report it killed — otherwise it keeps " <>
               "writing to the data dir while the freed GenServer admits a second run"
    end

    test "spawn_and_collect reports the OS pid and returns output with the exit status" do
      assert {"hello\n", 0} =
               Osmium.spawn_and_collect("echo", ["hello"], cd: File.cwd!(), report_to: self())

      assert_received {:osmium_os_pid, os_pid} when is_integer(os_pid)

      assert {"", 3} = Osmium.spawn_and_collect("sh", ["-c", "exit 3"], cd: File.cwd!())
    end

    test "an explicit timeout override is honoured" do
      Application.put_env(:atlas, :osmium_timeout, 20)
      on_exit(fn -> Application.delete_env(:atlas, :osmium_timeout) end)

      assert Osmium.call_timeout() == 20

      blocking_runner = fn _cmd, _args, _opts ->
        Process.sleep(500)
        {"done", 0}
      end

      start_supervised!({Osmium, runner: blocking_runner})

      assert catch_exit(
               Osmium.convert_to_osm_bz2("/work/data/osm", "current.osm.pbf", "out.partial")
             )
    end
  end
end
