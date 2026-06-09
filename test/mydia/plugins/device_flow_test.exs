defmodule Mydia.Plugins.DeviceFlowTest do
  use ExUnit.Case, async: true

  alias Mydia.Plugins.DeviceFlow

  setup do
    bypass = Bypass.open()

    descriptor = %{
      "type" => "oauth_device",
      "code_url" => "http://127.0.0.1:#{bypass.port}/oauth/pin?client_id={client_id}",
      "poll_url" => "http://127.0.0.1:#{bypass.port}/oauth/pin/{user_code}?client_id={client_id}",
      "verification_url" => "http://127.0.0.1:#{bypass.port}/pin"
    }

    %{bypass: bypass, descriptor: descriptor}
  end

  defp opts,
    do: [
      allowed_hosts: ["127.0.0.1"],
      slug: "t",
      allow_private: true,
      resolver: fn _ -> {:ok, [{127, 0, 0, 1}]} end
    ]

  describe "request_code/3" do
    test "parses the user code, verification url, and interval", %{
      bypass: bypass,
      descriptor: descriptor
    } do
      Bypass.expect_once(bypass, "GET", "/oauth/pin", fn conn ->
        Plug.Conn.resp(
          conn,
          200,
          ~s({"user_code":"AB12CD","verification_url":"https://simkl.com/pin","interval":5,"expires_in":900})
        )
      end)

      assert {:ok, result} = DeviceFlow.request_code(descriptor, "client-1", opts())
      assert result.user_code == "AB12CD"
      assert result.poll_token == "AB12CD"
      assert result.verification_url == "https://simkl.com/pin"
      assert result.interval_ms == 5000
      assert result.expires_in_s == 900
    end

    test "a response without a user code is an error", %{bypass: bypass, descriptor: descriptor} do
      Bypass.expect_once(bypass, "GET", "/oauth/pin", fn conn ->
        Plug.Conn.resp(conn, 200, ~s({"result":"KO"}))
      end)

      assert {:error, :no_user_code} = DeviceFlow.request_code(descriptor, "c", opts())
    end

    test "a host off the allowlist is blocked by the gate", %{descriptor: descriptor} do
      blocked = %{descriptor | "code_url" => "https://evil.test/pin?client_id={client_id}"}
      assert {:error, _} = DeviceFlow.request_code(blocked, "c", opts())
    end
  end

  describe "poll/4" do
    test "a token in a 200 body resolves authorized", %{bypass: bypass, descriptor: descriptor} do
      Bypass.expect_once(bypass, "GET", "/oauth/pin/CODE", fn conn ->
        Plug.Conn.resp(conn, 200, ~s({"result":"OK","access_token":"the-token"}))
      end)

      assert {:ok, %{access_token: "the-token"}} =
               DeviceFlow.poll(descriptor, "CODE", "c", opts())
    end

    test "a 200 KO body is pending", %{bypass: bypass, descriptor: descriptor} do
      Bypass.expect_once(bypass, "GET", "/oauth/pin/CODE", fn conn ->
        Plug.Conn.resp(conn, 200, ~s({"result":"KO"}))
      end)

      assert :pending = DeviceFlow.poll(descriptor, "CODE", "c", opts())
    end

    test "a 429 signals slow down", %{bypass: bypass, descriptor: descriptor} do
      Bypass.expect_once(bypass, "GET", "/oauth/pin/CODE", fn conn ->
        Plug.Conn.resp(conn, 429, "")
      end)

      assert :slow_down = DeviceFlow.poll(descriptor, "CODE", "c", opts())
    end

    test "a standard expired_token error is terminal", %{bypass: bypass, descriptor: descriptor} do
      Bypass.expect_once(bypass, "GET", "/oauth/pin/CODE", fn conn ->
        Plug.Conn.resp(conn, 400, ~s({"error":"expired_token"}))
      end)

      assert :expired = DeviceFlow.poll(descriptor, "CODE", "c", opts())
    end

    test "a standard access_denied error is terminal", %{bypass: bypass, descriptor: descriptor} do
      Bypass.expect_once(bypass, "GET", "/oauth/pin/CODE", fn conn ->
        Plug.Conn.resp(conn, 400, ~s({"error":"access_denied"}))
      end)

      assert :denied = DeviceFlow.poll(descriptor, "CODE", "c", opts())
    end

    test "the poll url substitutes the user code", %{bypass: bypass, descriptor: descriptor} do
      Bypass.expect_once(bypass, "GET", "/oauth/pin/XYZ", fn conn ->
        Plug.Conn.resp(conn, 200, ~s({"access_token":"t"}))
      end)

      assert {:ok, _} = DeviceFlow.poll(descriptor, "XYZ", "c", opts())
    end
  end
end
