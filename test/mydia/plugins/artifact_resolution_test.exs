defmodule Mydia.Plugins.ArtifactResolutionTest do
  use ExUnit.Case, async: true

  alias Mydia.Plugins
  alias Mydia.Plugins.Error

  @moduletag :tmp_dir

  defp config(slug, wasm), do: %{slug: slug, wasm_module: wasm}

  defp write(dir, name, bytes) do
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, name), bytes)
    dir
  end

  describe "resolve_artifact/2 layer precedence" do
    test "override dir wins over DB blob and bundled", %{tmp_dir: dir} do
      override = write(Path.join(dir, "override"), "webhook_notifier.wasm", "OVERRIDE")
      bundled = write(Path.join(dir, "bundled"), "webhook_notifier.wasm", "BUNDLED")

      assert {:ok, "OVERRIDE"} =
               Plugins.resolve_artifact(config("webhook-notifier", "DBBYTES"),
                 override_dir: override,
                 bundled_dir: bundled
               )
    end

    test "DB blob is used when the override dir is absent (index plugin)", %{tmp_dir: dir} do
      assert {:ok, "DBBYTES"} =
               Plugins.resolve_artifact(config("an-index-plugin", "DBBYTES"),
                 override_dir: nil,
                 bundled_dir: Path.join(dir, "none")
               )
    end

    test "bundled is used when override and DB are absent; hyphen slug maps to underscore file",
         %{tmp_dir: dir} do
      bundled = write(Path.join(dir, "bundled"), "webhook_notifier.wasm", "BUNDLED")

      assert {:ok, "BUNDLED"} =
               Plugins.resolve_artifact(config("webhook-notifier", nil),
                 override_dir: nil,
                 bundled_dir: bundled
               )
    end
  end

  describe "resolve_artifact/2 override filename + safety" do
    test "override matches an operator file named with the hyphenated slug", %{tmp_dir: dir} do
      override = write(Path.join(dir, "o"), "webhook-notifier.wasm", "HYPHEN")

      assert {:ok, "HYPHEN"} =
               Plugins.resolve_artifact(config("webhook-notifier", nil),
                 override_dir: override,
                 bundled_dir: Path.join(dir, "none")
               )
    end

    test "override near-miss falls through to the bundled layer", %{tmp_dir: dir} do
      override = write(Path.join(dir, "o"), "unrelated.wasm", "X")
      bundled = write(Path.join(dir, "b"), "webhook_notifier.wasm", "BUNDLED")

      assert {:ok, "BUNDLED"} =
               Plugins.resolve_artifact(config("webhook-notifier", nil),
                 override_dir: override,
                 bundled_dir: bundled
               )
    end

    test "traversal guard rejects a candidate escaping the dirs", %{tmp_dir: dir} do
      override = Path.join(dir, "o")
      File.mkdir_p!(override)
      # A secret sits one level above both the override and bundled dirs.
      File.write!(Path.join(dir, "secret.wasm"), "SECRET")

      # A slug crafted to escape via ../ must not read the secret at any layer.
      assert {:error, %Error{type: :invalid_config}} =
               Plugins.resolve_artifact(config("../secret", nil),
                 override_dir: override,
                 bundled_dir: Path.join(dir, "b")
               )
    end

    test "no artifact in any layer returns an error", %{tmp_dir: dir} do
      assert {:error, %Error{type: :invalid_config}} =
               Plugins.resolve_artifact(config("ghost", nil),
                 override_dir: Path.join(dir, "none"),
                 bundled_dir: Path.join(dir, "none")
               )
    end
  end
end
