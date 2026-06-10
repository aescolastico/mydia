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

  describe "wasm_target_missing?/1 (toolchain-gap classification)" do
    test "true for the cargo/rustc missing-target signatures" do
      assert Plugins.wasm_target_missing?(
               "note: the `wasm32-unknown-unknown` target may not be installed"
             )

      assert Plugins.wasm_target_missing?(
               "help: consider downloading the target with `rustup target add wasm32-unknown-unknown`"
             )

      assert Plugins.wasm_target_missing?("error[E0463]: can't find crate for `core`")
      assert Plugins.wasm_target_missing?("can't find crate for `std`")
    end

    test "false for a genuine guest source error" do
      refute Plugins.wasm_target_missing?("error[E0425]: cannot find value `foo` in this scope")
    end
  end

  describe "toolchain_gap_message/2 (loud skip, never silent)" do
    test "warns the existing artifacts may be stale when none are missing" do
      msg = Plugins.toolchain_gap_message("cargo not found on PATH", [])

      assert msg =~ "WARNING"
      assert msg =~ "cargo not found on PATH"
      assert msg =~ "STALE"
      assert msg =~ "rustup target add"
    end

    test "names missing artifacts that will not load" do
      msg =
        Plugins.toolchain_gap_message(
          "the wasm32-unknown-unknown rust target is not installed",
          ["priv/plugins/webhook_notifier.wasm"]
        )

      assert msg =~ "WARNING"
      assert msg =~ "MISSING"
      assert msg =~ "priv/plugins/webhook_notifier.wasm"
      assert msg =~ "will not load"
    end
  end

  describe "output_fresh?/3 (stale-artifact guard)" do
    setup %{tmp_dir: dir} do
      out = Path.join(dir, "demo.wasm")
      File.write!(out, "FRESH")
      {:ok, out: out, sha: sha("FRESH")}
    end

    test "true when digest matches and the artifact matches its recorded hash", %{
      out: out,
      sha: sha
    } do
      assert Plugins.output_fresh?({"D", sha}, "D", out)
    end

    test "false when the on-disk artifact no longer matches the recorded hash", %{
      out: out,
      sha: sha
    } do
      File.write!(out, "STALE")
      refute Plugins.output_fresh?({"D", sha}, "D", out)
    end

    test "false when the source digest changed", %{out: out, sha: sha} do
      refute Plugins.output_fresh?({"OLD", sha}, "NEW", out)
    end

    test "false when the artifact is missing", %{tmp_dir: dir} do
      refute Plugins.output_fresh?({"D", "abc"}, "D", Path.join(dir, "missing.wasm"))
    end

    test "false for a v1 (digest-only) cache entry", %{out: out} do
      refute Plugins.output_fresh?("D", "D", out)
    end
  end

  defp sha(bytes), do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)

  defp new_crate(base, name, body) do
    crate = Path.join(base, name)
    File.mkdir_p!(Path.join(crate, "src"))
    File.write!(Path.join(crate, "Cargo.toml"), "[package]\nname = \"#{name}\"\n")
    File.write!(Path.join([crate, "src", "lib.rs"]), body)
    crate
  end
end
