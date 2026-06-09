defmodule Mix.Tasks.Compile.PluginsTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Compile.Plugins

  @moduletag :tmp_dir

  describe "source_digest/1 (incremental guard core)" do
    test "is stable across calls for unchanged sources", %{tmp_dir: dir} do
      crate = new_crate(dir, "demo", "fn a() {}")

      assert Plugins.source_digest(crate) == Plugins.source_digest(crate)
    end

    test "changes when a source file changes", %{tmp_dir: dir} do
      crate = new_crate(dir, "demo", "fn a() {}")
      before = Plugins.source_digest(crate)

      File.write!(Path.join([crate, "src", "lib.rs"]), "fn b() {}")

      refute Plugins.source_digest(crate) == before
    end

    test "ignores target/ contents (so build output never feeds the digest)", %{tmp_dir: dir} do
      crate = new_crate(dir, "demo", "fn a() {}")
      before = Plugins.source_digest(crate)

      # Simulate cargo writing build artifacts under target/.
      File.mkdir_p!(Path.join([crate, "target", "wasm32-unknown-unknown", "release"]))

      File.write!(
        Path.join([crate, "target", "wasm32-unknown-unknown", "release", "demo.wasm"]),
        "BYTES"
      )

      assert Plugins.source_digest(crate) == before
    end

    test "is sensitive to file path, not just content", %{tmp_dir: dir} do
      crate_a = new_crate(Path.join(dir, "a"), "demo", "fn a() {}")
      # Same body, different filename under src/ → different digest.
      crate_b = new_crate(Path.join(dir, "b"), "demo", "fn a() {}")
      File.rename!(Path.join([crate_b, "src", "lib.rs"]), Path.join([crate_b, "src", "main.rs"]))

      refute Plugins.source_digest(crate_a) == Plugins.source_digest(crate_b)
    end
  end

  defp new_crate(base, name, body) do
    crate = Path.join(base, name)
    File.mkdir_p!(Path.join(crate, "src"))
    File.write!(Path.join(crate, "Cargo.toml"), "[package]\nname = \"#{name}\"\n")
    File.write!(Path.join([crate, "src", "lib.rs"]), body)
    crate
  end
end
