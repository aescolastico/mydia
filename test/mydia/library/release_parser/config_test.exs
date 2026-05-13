defmodule Mydia.Library.ReleaseParser.ConfigTest do
  use ExUnit.Case, async: false

  alias Mydia.Library.ReleaseParser.Config

  setup do
    original = Application.get_env(:mydia, :release_parser)

    on_exit(fn ->
      case original do
        nil -> Application.delete_env(:mydia, :release_parser)
        value -> Application.put_env(:mydia, :release_parser, value)
      end
    end)

    :ok
  end

  describe "commit_threshold/0" do
    test "defaults to 0.75 when no config is set" do
      Application.delete_env(:mydia, :release_parser)
      assert Config.commit_threshold() == 0.75
    end

    test "reads from :mydia, :release_parser, :commit_threshold" do
      Application.put_env(:mydia, :release_parser, commit_threshold: 0.9)
      assert Config.commit_threshold() == 0.9
    end

    test "falls back to default when key is missing in config" do
      Application.put_env(:mydia, :release_parser, suggest_threshold: 0.3)
      assert Config.commit_threshold() == 0.75
    end
  end

  describe "suggest_threshold/0" do
    test "defaults to 0.50 when no config is set" do
      Application.delete_env(:mydia, :release_parser)
      assert Config.suggest_threshold() == 0.50
    end

    test "reads from :mydia, :release_parser, :suggest_threshold" do
      Application.put_env(:mydia, :release_parser, suggest_threshold: 0.35)
      assert Config.suggest_threshold() == 0.35
    end
  end
end
