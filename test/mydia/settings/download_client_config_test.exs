defmodule Mydia.Settings.DownloadClientConfigTest do
  use Mydia.DataCase, async: true

  alias Mydia.Settings
  alias Mydia.Settings.DownloadClientConfig

  @valid_attrs %{
    name: "test-sab",
    type: :sabnzbd,
    enabled: true,
    priority: 1,
    host: "localhost",
    port: 8080,
    use_ssl: false,
    api_key: "test-api-key"
  }

  describe "wave-2 schema additions" do
    test "inserting with a categories map round-trips correctly" do
      categories = %{"movie" => "movies", "tv" => "tv", "music" => "music"}
      attrs = Map.put(@valid_attrs, :categories, categories)

      {:ok, config} = Settings.create_download_client_config(attrs)
      assert config.categories == categories

      # Round-trip through the DB (reload)
      reloaded = Repo.get!(DownloadClientConfig, config.id)
      assert reloaded.categories == categories
    end

    test "inserting with a priority_profile map round-trips correctly" do
      profile = %{"verylow" => -100, "low" => -50, "normal" => 0, "high" => 50, "veryhigh" => 100}
      attrs = Map.put(@valid_attrs, :priority_profile, profile)

      {:ok, config} = Settings.create_download_client_config(attrs)
      assert config.priority_profile == profile

      reloaded = Repo.get!(DownloadClientConfig, config.id)
      assert reloaded.priority_profile == profile
    end

    test "incomplete_grace_minutes defaults to 60 when not provided" do
      {:ok, config} = Settings.create_download_client_config(@valid_attrs)
      assert config.incomplete_grace_minutes == 60
    end

    test "incomplete_grace_minutes accepts a positive integer" do
      attrs = Map.put(@valid_attrs, :incomplete_grace_minutes, 30)
      {:ok, config} = Settings.create_download_client_config(attrs)
      assert config.incomplete_grace_minutes == 30
    end

    test "incomplete_grace_minutes: -1 fails validation" do
      attrs = Map.put(@valid_attrs, :incomplete_grace_minutes, -1)

      assert {:error, changeset} = Settings.create_download_client_config(attrs)
      refute changeset.valid?
      assert "must be greater than 0" in errors_on(changeset).incomplete_grace_minutes
    end

    test "incomplete_grace_minutes: 0 fails validation" do
      attrs = Map.put(@valid_attrs, :incomplete_grace_minutes, 0)

      assert {:error, changeset} = Settings.create_download_client_config(attrs)
      refute changeset.valid?
      assert "must be greater than 0" in errors_on(changeset).incomplete_grace_minutes
    end

    test "categories and priority_profile default to empty maps" do
      {:ok, config} = Settings.create_download_client_config(@valid_attrs)
      assert config.categories == %{}
      assert config.priority_profile == %{}
    end

    test "existing :category field still works alongside :categories map" do
      attrs =
        @valid_attrs
        |> Map.put(:category, "legacy-cat")
        |> Map.put(:categories, %{"movie" => "movies"})

      {:ok, config} = Settings.create_download_client_config(attrs)
      assert config.category == "legacy-cat"
      assert config.categories == %{"movie" => "movies"}
    end

    test "priority_profile with all 5 taxonomy keys is accepted" do
      profile = %{
        "verylow" => "-100",
        "low" => "-1",
        "normal" => "0",
        "high" => "1",
        "veryhigh" => "2"
      }

      attrs = Map.put(@valid_attrs, :priority_profile, profile)
      assert {:ok, config} = Settings.create_download_client_config(attrs)
      assert config.priority_profile == profile
    end

    test "priority_profile with unknown key is rejected" do
      profile = %{"high" => "1", "turbo" => "9"}
      attrs = Map.put(@valid_attrs, :priority_profile, profile)

      changeset = DownloadClientConfig.changeset(%DownloadClientConfig{}, attrs)
      refute changeset.valid?

      [msg | _] = errors_on(changeset).priority_profile
      assert msg =~ "unknown priority key"
      assert msg =~ "turbo"
    end

    test "priority_profile that is not a map is rejected" do
      attrs = Map.put(@valid_attrs, :priority_profile, "not-a-map")
      changeset = DownloadClientConfig.changeset(%DownloadClientConfig{}, attrs)
      refute changeset.valid?
    end
  end
end
