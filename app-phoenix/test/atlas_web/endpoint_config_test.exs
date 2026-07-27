defmodule AtlasWeb.EndpointConfigTest do
  use ExUnit.Case, async: true

  import Plug.Test, only: [conn: 2]

  alias AtlasWeb.EndpointConfig

  describe "url/1 defaults" do
    test "keeps the public HTTPS defaults when nothing is set" do
      assert EndpointConfig.url(%{"PHX_HOST" => "atlas.example.com"}) ==
               [host: "atlas.example.com", port: 443, scheme: "https"]
    end

    test "falls back to example.com when PHX_HOST is unset" do
      assert EndpointConfig.url(%{})[:host] == "example.com"
    end
  end

  describe "url/1 with PHX_SCHEME=http" do
    test "defaults the port to 80" do
      assert EndpointConfig.url(%{"PHX_HOST" => "192.168.5.99", "PHX_SCHEME" => "http"}) ==
               [host: "192.168.5.99", port: 80, scheme: "http"]
    end

    test "honours an explicit non-standard port" do
      env = %{"PHX_HOST" => "192.168.5.99", "PHX_SCHEME" => "http", "PHX_PORT" => "8484"}

      assert EndpointConfig.url(env) ==
               [host: "192.168.5.99", port: 8484, scheme: "http"]
    end
  end

  describe "force_ssl?/1" do
    test "defaults to true so public deployments stay protected" do
      assert EndpointConfig.force_ssl?(%{})
    end

    test "defaults to false when the public scheme is plain http" do
      refute EndpointConfig.force_ssl?(%{"PHX_SCHEME" => "http"})
    end

    test "an explicit FORCE_SSL=false disables the redirect on https" do
      refute EndpointConfig.force_ssl?(%{"FORCE_SSL" => "false"})
      refute EndpointConfig.force_ssl?(%{"FORCE_SSL" => "0"})
    end

    test "an explicit FORCE_SSL=true wins over an http scheme" do
      assert EndpointConfig.force_ssl?(%{"PHX_SCHEME" => "http", "FORCE_SSL" => "true"})
    end
  end

  describe "check_origin/1" do
    test "defaults to true, which validates against the resolved url config" do
      assert EndpointConfig.check_origin(%{}) == true
    end

    test "can be disabled outright" do
      assert EndpointConfig.check_origin(%{"PHX_CHECK_ORIGIN" => "false"}) == false
    end

    test "accepts an explicit comma-separated allow list" do
      env = %{"PHX_CHECK_ORIGIN" => "http://192.168.5.99:8484,https://atlas.example.com"}

      assert EndpointConfig.check_origin(env) ==
               ["http://192.168.5.99:8484", "https://atlas.example.com"]
    end

    test "trims whitespace and drops empty entries in the allow list" do
      env = %{"PHX_CHECK_ORIGIN" => " http://a.test , , https://b.test "}

      assert EndpointConfig.check_origin(env) == ["http://a.test", "https://b.test"]
    end
  end

  describe "skip_https_redirect?/1 (Plug.SSL runtime gate)" do
    setup do
      original = Application.get_env(:atlas, :force_ssl)
      on_exit(fn -> Application.put_env(:atlas, :force_ssl, original) end)
    end

    test "does not skip while force_ssl is on" do
      Application.put_env(:atlas, :force_ssl, true)

      refute EndpointConfig.skip_https_redirect?(%Plug.Conn{})
    end

    test "skips every request once force_ssl is turned off at runtime" do
      Application.put_env(:atlas, :force_ssl, false)

      assert EndpointConfig.skip_https_redirect?(%Plug.Conn{})
    end
  end

  describe "the shipped prod force_ssl config, driven through Plug.SSL" do
    setup do
      original = Application.get_env(:atlas, :force_ssl)
      on_exit(fn -> Application.put_env(:atlas, :force_ssl, original) end)

      opts =
        "config/prod.exs"
        |> Config.Reader.read!(env: :prod)
        |> get_in([:atlas, AtlasWeb.Endpoint, :force_ssl])

      {:ok, init: Plug.SSL.init(opts)}
    end

    test "redirects plain HTTP to HTTPS while force_ssl is on", %{init: init} do
      Application.put_env(:atlas, :force_ssl, true)

      out = Plug.SSL.call(conn(:get, "http://atlas.example.com/"), init)

      assert out.status == 301
      assert out.halted
    end

    test "serves plain HTTP untouched once FORCE_SSL is off", %{init: init} do
      Application.put_env(:atlas, :force_ssl, false)

      out = Plug.SSL.call(conn(:get, "http://192.168.5.99:8484/"), init)

      refute out.halted
      assert out.status == nil
    end

    test "localhost stays excluded regardless", %{init: init} do
      Application.put_env(:atlas, :force_ssl, true)

      out = Plug.SSL.call(conn(:get, "http://localhost:4000/"), init)

      refute out.halted
    end
  end
end
