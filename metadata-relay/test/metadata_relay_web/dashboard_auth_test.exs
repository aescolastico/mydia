defmodule MetadataRelayWeb.DashboardAuthTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Plug.Conn

  @endpoint MetadataRelayWeb.Endpoint

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(MetadataRelay.Repo)
    :ok
  end

  test "GET /feedback requires credentials" do
    conn = get(build_conn(), "/feedback")

    assert conn.status == 401
    assert [www_authenticate] = get_resp_header(conn, "www-authenticate")
    assert www_authenticate =~ "Metadata Relay Dashboard"
  end

  test "GET /feedback rejects wrong credentials" do
    conn =
      build_conn()
      |> put_req_header("authorization", basic_auth("admin", "wrong"))
      |> get("/feedback")

    assert conn.status == 401
  end

  test "GET /errors requires credentials" do
    conn = get(build_conn(), "/errors")

    assert conn.status == 401
    assert [_www_authenticate] = get_resp_header(conn, "www-authenticate")
  end

  defp basic_auth(username, password) do
    "Basic " <> Base.encode64("#{username}:#{password}")
  end
end
