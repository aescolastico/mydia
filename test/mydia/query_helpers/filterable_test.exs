defmodule Mydia.QueryHelpers.FilterableTest do
  use Mydia.DataCase

  alias Mydia.Repo
  alias Mydia.Accounts.User
  alias Mydia.Settings.QualityProfile

  # Test module that uses the Filterable macro with eq + allowlist
  defmodule UserFilters do
    use Mydia.QueryHelpers.Filterable,
      function_name: :apply_user_filters,
      filters: [
        role: {:eq, values: ["admin", "user"]}
      ]

    import Ecto.Query, warn: false

    def list(opts \\ []) do
      User
      |> apply_user_filters(opts)
      |> Repo.all()
    end
  end

  # Test module with simple equality filters (no values constraint)
  defmodule SimpleFilters do
    use Mydia.QueryHelpers.Filterable,
      filters: [
        role: :eq,
        email: :eq
      ]

    import Ecto.Query, warn: false

    def list(opts \\ []) do
      User
      |> apply_filters(opts)
      |> Repo.all()
    end
  end

  # Test module exercising the :boolean filter against a real boolean column
  defmodule ProfileFilters do
    use Mydia.QueryHelpers.Filterable,
      function_name: :apply_profile_filters,
      filters: [
        is_system: :boolean
      ]

    import Ecto.Query, warn: false

    def list(opts \\ []) do
      QualityProfile
      |> apply_profile_filters(opts)
      |> Repo.all()
    end
  end

  import Mydia.AccountsFixtures
  import Mydia.SettingsFixtures

  describe "eq filter with values constraint" do
    test "filters by allowed value" do
      admin = user_fixture(%{role: "admin"})
      _user = user_fixture(%{role: "user"})

      results = UserFilters.list(role: "admin")
      assert length(results) == 1
      assert hd(results).id == admin.id
    end

    test "ignores disallowed value" do
      _admin = user_fixture(%{role: "admin"})
      user = user_fixture(%{role: "user"})

      # "invalid" is not in the values list, so it's ignored (returns all)
      results = UserFilters.list(role: "invalid")
      assert length(results) >= 2
      assert Enum.any?(results, &(&1.id == user.id))
    end
  end

  describe "eq filter without values constraint" do
    test "filters by any non-nil value" do
      admin = user_fixture(%{role: "admin"})
      _user = user_fixture(%{role: "user"})

      results = SimpleFilters.list(role: "admin")
      assert length(results) == 1
      assert hd(results).id == admin.id
    end

    test "skips nil value" do
      _admin = user_fixture(%{role: "admin"})
      _user = user_fixture(%{role: "user"})

      results = SimpleFilters.list(role: nil)
      assert length(results) >= 2
    end
  end

  describe "boolean filter" do
    test "filters by true" do
      profile = quality_profile_fixture(%{qualities: ["1080p", "720p"]})
      # System profiles are seeded/created elsewhere; just verify non-system profiles are excluded
      results = ProfileFilters.list(is_system: false)

      assert Enum.any?(results, &(&1.id == profile.id))
      assert Enum.all?(results, &(&1.is_system == false))
    end

    test "filters by false" do
      _profile = quality_profile_fixture(%{qualities: ["1080p", "720p"]})
      results = ProfileFilters.list(is_system: true)

      assert Enum.all?(results, &(&1.is_system == true))
    end

    test "skips non-boolean values" do
      profile = quality_profile_fixture(%{qualities: ["1080p", "720p"]})

      # Non-boolean values fail the guard and fall through to the catch-all
      results = ProfileFilters.list(is_system: "not_a_boolean")
      assert Enum.any?(results, &(&1.id == profile.id))
    end

    test "skips nil" do
      profile = quality_profile_fixture(%{qualities: ["1080p", "720p"]})

      results = ProfileFilters.list(is_system: nil)
      assert Enum.any?(results, &(&1.id == profile.id))
    end
  end

  describe "unknown filters are ignored" do
    test "passes through unknown option keys" do
      _user = user_fixture()

      # Unknown options should be silently ignored
      results = UserFilters.list(unknown_key: "value", preload: [:sessions])
      assert is_list(results)
    end
  end

  describe "multiple filters combined" do
    test "applies multiple filters" do
      admin = user_fixture(%{role: "admin", email: "admin@mydia.test"})
      _user = user_fixture(%{email: "user@mydia.test"})
      _other_admin = user_fixture(%{role: "admin", email: "other@different.org"})

      results = SimpleFilters.list(role: "admin", email: "admin@mydia.test")
      assert length(results) == 1
      assert hd(results).id == admin.id
    end
  end
end
