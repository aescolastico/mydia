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

  describe "rqbit client type" do
    @rqbit_attrs %{
      name: "test-rqbit",
      type: :rqbit,
      enabled: true,
      priority: 1,
      host: "localhost",
      port: 3030,
      use_ssl: false
    }

    test "a rqbit config with host and port is valid" do
      {:ok, config} = Settings.create_download_client_config(@rqbit_attrs)
      assert config.type == :rqbit
      assert config.host == "localhost"
      assert config.port == 3030
    end

    test "rqbit requires host and port (network client validation)" do
      changeset =
        DownloadClientConfig.changeset(%DownloadClientConfig{}, %{@rqbit_attrs | host: nil})

      refute changeset.valid?
      assert %{host: _} = errors_on(changeset)
    end
  end

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

  describe "debrid client validation" do
    @debrid_attrs %{
      name: "my-rd",
      type: :debrid,
      enabled: true,
      priority: 1,
      api_key: "rd-token-123",
      connection_settings: %{"provider" => "real_debrid"}
    }

    test "valid debrid config (api_key + connection_settings.provider) is accepted" do
      assert {:ok, config} = Settings.create_download_client_config(@debrid_attrs)
      assert config.type == :debrid
      assert config.api_key == "rd-token-123"
      assert config.connection_settings == %{"provider" => "real_debrid"}
    end

    test "host and port are not required for debrid (and not rejected if provided)" do
      attrs = Map.merge(@debrid_attrs, %{host: "ignored", port: 9999})
      assert {:ok, config} = Settings.create_download_client_config(attrs)
      assert config.host == "ignored"
      assert config.port == 9999
    end

    test "incomplete_grace_minutes defaults to 1440 for debrid when not provided" do
      assert {:ok, config} = Settings.create_download_client_config(@debrid_attrs)
      assert config.incomplete_grace_minutes == 1440
    end

    test "explicit incomplete_grace_minutes is preserved for debrid" do
      attrs = Map.put(@debrid_attrs, :incomplete_grace_minutes, 60)
      assert {:ok, config} = Settings.create_download_client_config(attrs)
      assert config.incomplete_grace_minutes == 60
    end

    test "missing api_key produces a blank error" do
      attrs = Map.delete(@debrid_attrs, :api_key)

      assert {:error, changeset} = Settings.create_download_client_config(attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).api_key
    end

    test "missing connection_settings.provider produces an error naming the valid choices" do
      attrs = Map.put(@debrid_attrs, :connection_settings, %{})

      assert {:error, changeset} = Settings.create_download_client_config(attrs)
      refute changeset.valid?

      [msg | _] = errors_on(changeset).connection_settings
      assert msg =~ "provider"
      assert msg =~ "real_debrid"
      assert msg =~ "all_debrid"
      assert msg =~ "premiumize"
      assert msg =~ "tor_box"
    end

    test "unknown provider value is rejected" do
      attrs = Map.put(@debrid_attrs, :connection_settings, %{"provider" => "unknown"})

      assert {:error, changeset} = Settings.create_download_client_config(attrs)
      refute changeset.valid?

      [msg | _] = errors_on(changeset).connection_settings
      assert msg =~ "unknown"
      assert msg =~ "real_debrid"
    end

    test "each of the four valid providers is accepted" do
      for provider <- ["real_debrid", "all_debrid", "premiumize", "tor_box"] do
        attrs =
          @debrid_attrs
          |> Map.put(:name, "my-#{provider}")
          |> Map.put(:connection_settings, %{"provider" => provider})

        assert {:ok, config} = Settings.create_download_client_config(attrs)
        assert config.connection_settings == %{"provider" => provider}
      end
    end

    test "debrid_providers/0 returns the four supported provider strings" do
      assert DownloadClientConfig.debrid_providers() == [
               "real_debrid",
               "all_debrid",
               "premiumize",
               "tor_box"
             ]
    end
  end
end
