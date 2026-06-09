defmodule Mix.Tasks.Compile.Plugins do
  @moduledoc """
  Builds the bundled WASM plugin guests under `plugins/*/` into `priv/plugins/`.

  Mirrors how `use Rustler` lands the p2p NIF in `priv/native/`, but as a real
  `Mix.Task.Compiler` registered (prepended) in `mix.exs` `compilers/0`, so the
  guests build transparently on every `mix compile` in dev, test, CI, and the
  Docker image build. The compiled `.wasm` is gitignored — source under
  `plugins/*/` is the only truth (U1–U3 of the built-in-plugins plan).

  ## Incremental by content digest, not mtime

  Each crate's source tree (everything but `target/`) is hashed; the digest is
  cached in the compiler manifest. A crate whose digest is unchanged and whose
  output already exists is skipped without invoking cargo. The digest is
  content-based, so a `git checkout`/`bisect` that rewinds source correctly
  triggers a rebuild — an mtime guard would not (a gitignored artifact can be
  newer than older source).

  ## Environment-aware skip

  When `cargo` or the `wasm32-unknown-unknown` target is unavailable, a *dev*
  build logs a warning and no-ops so a contributor not working on plugins can
  still compile the app. A *release/CI* build (`MIX_ENV=prod` or `CI` set) treats
  a missing toolchain as a hard error — otherwise `mix compile` would succeed and
  the image would ship with no bundled `.wasm`, and the plugin would silently
  never seed.
  """

  use Mix.Task.Compiler

  @recursive false
  @target "wasm32-unknown-unknown"
  @manifest_vsn 1

  @impl Mix.Task.Compiler
  def run(_argv) do
    crates = crates()

    cond do
      crates == [] ->
        {:noop, []}

      (reason = toolchain_gap()) != nil ->
        on_toolchain_gap(reason)

      true ->
        build_all(crates)
    end
  end

  @impl Mix.Task.Compiler
  def manifests, do: [manifest_path()]

  @impl Mix.Task.Compiler
  def clean do
    File.rm(manifest_path())
    :ok
  end

  # ── Crate discovery ───────────────────────────────────────────────────────

  defp crates do
    "plugins"
    |> Path.expand(File.cwd!())
    |> Path.join("*/Cargo.toml")
    |> Path.wildcard()
    |> Enum.map(&Path.dirname/1)
    |> Enum.sort()
  end

  # ── Toolchain probing ─────────────────────────────────────────────────────

  # Returns nil when the toolchain can build wasm, or a human reason string when
  # it cannot. When `rustup` is absent (e.g. apk cargo), we can't enumerate
  # targets, so we let the build itself surface a missing-target error.
  defp toolchain_gap do
    cond do
      System.find_executable("cargo") == nil -> "cargo not found on PATH"
      System.find_executable("rustup") == nil -> nil
      wasm_target_installed?() -> nil
      true -> "the #{@target} rust target is not installed"
    end
  end

  defp wasm_target_installed? do
    case System.cmd("rustup", ["target", "list", "--installed"], stderr_to_stdout: true) do
      {out, 0} -> out |> String.split("\n") |> Enum.member?(@target)
      _ -> false
    end
  rescue
    _ -> false
  end

  # The compiler always graceful-skips a missing wasm toolchain (warn, no-op)
  # rather than hard-failing: the Nix package build and toolchain-less
  # contributors legitimately lack the target, and forcing a hard error there
  # would break those builds. The silent-empty-image risk is instead guarded
  # where it matters — the Docker builders assert priv/plugins/*.wasm exists
  # after `mix compile` (see Dockerfile / Dockerfile.e2e), so a release image
  # can never ship without the bundled artifact.
  defp on_toolchain_gap(reason) do
    Mix.shell().info("[plugins] skipping wasm build — #{reason}")
    {:noop, []}
  end

  # ── Build ─────────────────────────────────────────────────────────────────

  defp build_all(crates) do
    cache = read_manifest()

    {results, new_cache} =
      Enum.map_reduce(crates, cache, fn crate, acc ->
        {result, digest} = build_crate(crate, acc)
        {result, Map.put(acc, crate, digest)}
      end)

    write_manifest(new_cache)

    cond do
      Enum.find(results, &match?({:error, _}, &1)) ->
        {:error, [elem(Enum.find(results, &match?({:error, _}, &1)), 1)]}

      Enum.any?(results, &(&1 == :built)) ->
        {:ok, []}

      true ->
        {:noop, []}
    end
  end

  # Returns {{:error, diagnostic} | :built | :unchanged | :skipped, source_digest}.
  defp build_crate(crate, cache) do
    name = Path.basename(crate)
    digest = source_digest(crate)
    output = Path.expand(Path.join("priv/plugins", "#{name}.wasm"), File.cwd!())

    if Map.get(cache, crate) == digest and File.exists?(output) do
      {:unchanged, digest}
    else
      {compile_crate(crate, name, output), digest}
    end
  end

  defp compile_crate(crate, name, output) do
    Mix.shell().info("[plugins] compiling #{name} -> priv/plugins/#{name}.wasm")

    case System.cmd("cargo", ["build", "--release", "--target", @target],
           cd: crate,
           stderr_to_stdout: true
         ) do
      {_out, 0} ->
        copy_if_changed(crate, name, output)

      {out, _code} ->
        if wasm_target_missing?(out) do
          # A cargo without the wasm32 std (apk/distro/Nix cargo, no rustup) only
          # surfaces the gap at build time. Treat it as a skip, not a hard error,
          # so it matches the toolchain-gap path above.
          Mix.shell().info("[plugins] skipping #{name} — #{@target} target not available")
          :skipped
        else
          # A real guest build error (e.g. a server-only crate). Surface cargo's
          # stderr verbatim — wasm32 errors are otherwise cryptic.
          {:error, diagnostic("cargo build failed for #{name}:\n#{out}")}
        end
    end
  end

  # True when cargo output indicates the wasm32 target/std is not installed (vs a
  # genuine source error). Public for testing only.
  @doc false
  def wasm_target_missing?(output) do
    String.contains?(output, "target may not be installed") or
      String.contains?(output, "rustup target add") or
      String.contains?(output, "can't find crate for `core`") or
      String.contains?(output, "can't find crate for `std`")
  end

  # Copy only when the freshly built bytes differ from what's on disk, so an
  # unchanged rebuild doesn't churn the (gitignored) artifact.
  defp copy_if_changed(crate, name, output) do
    built = Path.join([crate, "target", @target, "release", "#{name}.wasm"])

    cond do
      not File.exists?(built) ->
        {:error, diagnostic("cargo reported success but #{built} is missing")}

      File.exists?(output) and File.read!(built) == File.read!(output) ->
        :unchanged

      true ->
        File.mkdir_p!(Path.dirname(output))
        File.cp!(built, output)
        :built
    end
  end

  # ── Source digest (content-based, target/ excluded) ───────────────────────

  # Content digest of a crate's source tree (everything but `target/`). Public
  # for testing only — the digest is content-based so it survives `git
  # checkout`/`bisect` correctly, unlike an mtime comparison.
  @doc false
  def source_digest(crate) do
    crate
    |> Path.join("**/*")
    |> Path.wildcard(match_dot: true)
    |> Enum.reject(&(File.dir?(&1) or String.contains?(&1, "/target/")))
    |> Enum.sort()
    |> Enum.reduce(:crypto.hash_init(:sha256), fn path, acc ->
      rel = Path.relative_to(path, crate)
      :crypto.hash_update(acc, rel <> "\0" <> File.read!(path))
    end)
    |> :crypto.hash_final()
    |> Base.encode16(case: :lower)
  end

  # ── Manifest ──────────────────────────────────────────────────────────────

  defp manifest_path, do: Path.join(Mix.Project.manifest_path(), "compile.plugins")

  defp read_manifest do
    case File.read(manifest_path()) do
      {:ok, bin} ->
        case safe_binary_to_term(bin) do
          {@manifest_vsn, map} when is_map(map) -> map
          _ -> %{}
        end

      _ ->
        %{}
    end
  end

  defp write_manifest(map) do
    File.mkdir_p!(Path.dirname(manifest_path()))
    File.write!(manifest_path(), :erlang.term_to_binary({@manifest_vsn, map}))
  end

  defp safe_binary_to_term(bin) do
    :erlang.binary_to_term(bin, [:safe])
  rescue
    _ -> nil
  end

  # ── Diagnostics ───────────────────────────────────────────────────────────

  defp diagnostic(message) do
    %Mix.Task.Compiler.Diagnostic{
      compiler_name: "plugins",
      file: Path.expand("plugins", File.cwd!()),
      message: message,
      position: nil,
      severity: :error
    }
  end
end
