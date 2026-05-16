defmodule Mydia.Feedback.SenderTest do
  use Mydia.DataCase

  alias Mydia.Feedback
  alias Mydia.Feedback.Sender

  setup do
    original = System.get_env("METADATA_RELAY_URL")

    on_exit(fn ->
      if original do
        System.put_env("METADATA_RELAY_URL", original)
      else
        System.delete_env("METADATA_RELAY_URL")
      end
    end)

    :ok
  end

  test "send/1 includes mydia_version and nil instance_id" do
    bypass = Bypass.open()
    System.put_env("METADATA_RELAY_URL", endpoint_url(bypass))

    Bypass.expect_once(bypass, "POST", "/feedback", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      payload = Jason.decode!(body)

      assert payload["type"] == "bug"
      assert payload["message"] == "Playback froze"
      assert payload["contact"] == nil
      assert payload["instance_id"] == nil
      assert payload["mydia_version"] == Mydia.System.app_version()

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(201, Jason.encode!(%{status: "created", id: "feedback-1"}))
    end)

    assert {:ok, %{id: "feedback-1"}} = Feedback.send(%{type: "bug", message: "Playback froze"})
  end

  test "post/1 returns ok on 201" do
    bypass = Bypass.open()
    System.put_env("METADATA_RELAY_URL", endpoint_url(bypass))

    Bypass.expect_once(bypass, "POST", "/feedback", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(201, Jason.encode!(%{id: "feedback-1"}))
    end)

    assert {:ok, %{id: "feedback-1"}} = Sender.post(%{type: "bug", message: "Bug"})
  end

  test "post/1 returns validation errors on 400" do
    bypass = Bypass.open()
    System.put_env("METADATA_RELAY_URL", endpoint_url(bypass))

    Bypass.expect_once(bypass, "POST", "/feedback", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(
        400,
        Jason.encode!(%{error: "Validation failed", errors: ["Missing required field: type"]})
      )
    end)

    assert {:error, {:validation_error, ["Missing required field: type"]}} =
             Sender.post(%{message: "Bug"})
  end

  test "post/1 returns rate limit retry_after on 429" do
    bypass = Bypass.open()
    System.put_env("METADATA_RELAY_URL", endpoint_url(bypass))

    Bypass.expect_once(bypass, "POST", "/feedback", fn conn ->
      conn
      |> Plug.Conn.put_resp_header("retry-after", "60")
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(429, Jason.encode!(%{error: "Too many requests"}))
    end)

    assert {:error, {:rate_limited, 60}} = Sender.post(%{type: "bug", message: "Bug"})
  end

  test "post/1 treats 404 as service unavailable for old relays" do
    bypass = Bypass.open()
    System.put_env("METADATA_RELAY_URL", endpoint_url(bypass))

    Bypass.expect_once(bypass, "POST", "/feedback", fn conn ->
      Plug.Conn.resp(conn, 404, "Not found")
    end)

    assert {:error, :service_unavailable} = Sender.post(%{type: "bug", message: "Bug"})
  end

  defp endpoint_url(bypass), do: "http://localhost:#{bypass.port}"
end
