defmodule MydiaWeb.ProfileLiveTest do
  # async: false — connected LiveView under the Postgres sandbox (rows inserted
  # in the test must be visible to the mount process).
  use MydiaWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  setup %{conn: conn} do
    {conn, user} = register_and_log_in_user(conn)
    %{conn: conn, user: user}
  end

  test "renders the profile page", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/profile")

    assert has_element?(view, "#profile-form")
  end

  test "links out to the dedicated Integrations page", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/profile")

    # Integrations moved to /integrations; the profile page only points to it.
    assert has_element?(view, "#integrations-link[href='/integrations']")
  end
end
