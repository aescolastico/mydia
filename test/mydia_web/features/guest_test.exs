defmodule MydiaWeb.Features.GuestTest do
  @moduledoc """
  Feature tests for the guest system: navigation, request pages,
  My Requests page, and admin request management.

  Search on request pages hits the external metadata-relay API,
  so we bypass search and pre-create request data directly via
  `MediaRequests.create_request/1`.
  """

  use MydiaWeb.FeatureCase, async: false

  alias Mydia.MediaRequests

  @moduletag :feature

  describe "Guest Navigation & Access Control" do
    @tag :feature
    test "guest can access dashboard after login", %{session: session} do
      login_as_guest(session)

      session
      |> wait_for_liveview()
      |> assert_path("/")
      |> assert_has_text("Dashboard")
    end

    @tag :feature
    test "guest sees request links in sidebar", %{session: session} do
      login_as_guest(session)

      session
      |> wait_for_liveview()
      |> assert_path("/")

      assert Wallaby.Browser.has_text?(session, "Request Movie")
      assert Wallaby.Browser.has_text?(session, "Request Series")
      assert Wallaby.Browser.has_text?(session, "My Requests")
    end

    @tag :feature
    test "guest can browse movies page", %{session: session} do
      login_as_guest(session)
      session |> wait_for_liveview()

      session
      |> visit("/movies")
      |> wait_for_liveview()
      |> assert_path("/movies")
    end

    @tag :feature
    test "guest cannot access admin pages", %{session: session} do
      login_as_guest(session)
      session |> wait_for_liveview()

      session
      |> visit("/admin/requests")
      |> wait_for_liveview()

      # Guest should be redirected away from admin page
      refute Wallaby.Browser.current_path(session) == "/admin/requests"
    end
  end

  describe "Request Media Pages" do
    @tag :feature
    test "guest can access request movie page", %{session: session} do
      login_as_guest(session)
      session |> wait_for_liveview()

      session
      |> visit("/request/movie")
      |> wait_for_liveview()
      |> assert_path("/request/movie")
      |> assert_has_text("Request Movie")
      |> assert_has_text("Guest Request System")

      assert Wallaby.Browser.has_css?(session, "#search-form")
    end

    @tag :feature
    test "guest can access request series page", %{session: session} do
      login_as_guest(session)
      session |> wait_for_liveview()

      session
      |> visit("/request/series")
      |> wait_for_liveview()
      |> assert_path("/request/series")
      |> assert_has_text("Request Series")

      assert Wallaby.Browser.has_css?(session, "#search-form")
    end
  end

  describe "My Requests Page" do
    @tag :feature
    test "shows empty state when no requests", %{session: session} do
      login_as_guest(session)
      session |> wait_for_liveview()

      session
      |> visit("/requests")
      |> wait_for_liveview()
      |> assert_path("/requests")
      |> assert_has_text("No requests found")
    end

    @tag :feature
    test "shows pending request when one exists", %{session: session} do
      guest = create_guest_user()
      login(session, guest.username, "password123")
      session |> wait_for_liveview()

      {:ok, _request} =
        MediaRequests.create_request(%{
          media_type: "movie",
          title: "Test Movie Alpha",
          tmdb_id: 99001,
          requester_id: guest.id
        })

      session
      |> visit("/requests")
      |> wait_for_liveview()
      |> assert_path("/requests")
      |> assert_has_text("Test Movie Alpha")
      |> assert_has_text("Pending")
    end

    @tag :feature
    test "filter tabs show correct requests", %{session: session} do
      guest = create_guest_user()
      admin = create_admin_user()

      login(session, guest.username, "password123")
      session |> wait_for_liveview()

      # Create a pending request
      {:ok, _pending} =
        MediaRequests.create_request(%{
          media_type: "movie",
          title: "Pending Film",
          tmdb_id: 99010,
          requester_id: guest.id
        })

      # Create and reject a request
      {:ok, rejected_req} =
        MediaRequests.create_request(%{
          media_type: "movie",
          title: "Rejected Film",
          tmdb_id: 99011,
          requester_id: guest.id
        })

      {:ok, _} =
        MediaRequests.reject_request(rejected_req, %{
          rejection_reason: "Not available",
          approved_by_id: admin.id
        })

      # Visit My Requests (default is "all")
      session
      |> visit("/requests")
      |> wait_for_liveview()

      # All tab should show both
      assert_has_text(session, "Pending Film")
      assert_has_text(session, "Rejected Film")

      # Click Pending tab
      session
      |> js_click("[phx-click='filter'][phx-value-status='pending']")

      assert_has_text(session, "Pending Film")
      refute Wallaby.Browser.has_text?(session, "Rejected Film")

      # Click Rejected tab
      session
      |> js_click("[phx-click='filter'][phx-value-status='rejected']")

      assert_has_text(session, "Rejected Film")
      refute Wallaby.Browser.has_text?(session, "Pending Film")
    end
  end

  describe "Admin Request Management" do
    @tag :feature
    test "admin can see pending guest requests", %{session: session} do
      guest = create_guest_user()
      admin = create_admin_user()

      {:ok, _request} =
        MediaRequests.create_request(%{
          media_type: "movie",
          title: "Guest Movie Request",
          tmdb_id: 99020,
          requester_id: guest.id
        })

      login(session, admin.username, "password123")
      session |> wait_for_liveview()

      session
      |> visit("/admin/requests")
      |> wait_for_liveview()
      |> assert_path("/admin/requests")
      |> assert_has_text("Guest Movie Request")
      |> assert_has_text("Pending")
    end

    @tag :feature
    @tag timeout: 120_000
    test "admin can approve a request", %{session: session} do
      guest = create_guest_user()
      admin = create_admin_user()

      {:ok, _request} =
        MediaRequests.create_request(%{
          media_type: "movie",
          title: "Approvable Movie",
          tmdb_id: 99030,
          requester_id: guest.id
        })

      login(session, admin.username, "password123")
      session |> wait_for_liveview()

      session
      |> visit("/admin/requests")
      |> wait_for_liveview()
      |> assert_has_text("Approvable Movie")

      # Click Approve button to open modal
      session |> js_click("[phx-click='open_approve_modal']")

      assert Wallaby.Browser.has_css?(session, "#approve-form")

      # Submit the approve form via requestSubmit (triggers LiveView phx-submit)
      Wallaby.Browser.execute_script(session, """
        var form = document.getElementById('approve-form');
        if (form) { form.requestSubmit(); }
      """)

      :timer.sleep(3000)

      # Use page_source assertion to avoid chromedriver log endpoint hang
      assert_page_contains(session, "approved")
    end

    @tag :feature
    @tag timeout: 120_000
    test "admin can reject a request with reason", %{session: session} do
      guest = create_guest_user()
      admin = create_admin_user()

      {:ok, _request} =
        MediaRequests.create_request(%{
          media_type: "movie",
          title: "Rejectable Movie",
          tmdb_id: 99040,
          requester_id: guest.id
        })

      login(session, admin.username, "password123")
      session |> wait_for_liveview()

      session
      |> visit("/admin/requests")
      |> wait_for_liveview()
      |> assert_has_text("Rejectable Movie")

      # Click Reject button to open modal
      session |> js_click("[phx-click='open_reject_modal']")

      assert Wallaby.Browser.has_css?(session, "#reject-form")

      # Fill in rejection reason and submit via JS
      Wallaby.Browser.execute_script(session, """
        var textarea = document.querySelector("#reject-form textarea[name='reject[rejection_reason]']");
        if (textarea) {
          var nativeInputValueSetter = Object.getOwnPropertyDescriptor(window.HTMLTextAreaElement.prototype, 'value').set;
          nativeInputValueSetter.call(textarea, 'Not suitable for library');
          textarea.dispatchEvent(new Event('input', { bubbles: true }));
        }
      """)

      :timer.sleep(1000)

      # Submit the reject form via requestSubmit (triggers LiveView phx-submit)
      Wallaby.Browser.execute_script(session, """
        var form = document.getElementById('reject-form');
        if (form) { form.requestSubmit(); }
      """)

      :timer.sleep(3000)

      # Use page_source assertion to avoid chromedriver log endpoint hang
      assert_page_contains(session, "rejected")
    end
  end
end
