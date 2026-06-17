{ pkgs, lib, config, ... }:

# Mydia developer environment (devenv.sh).
#
# Replaces the Docker-based `./dev` toolchain. The daily loop (Phoenix server,
# `mix test`, `mix precommit`, Flutter codegen) runs natively in this shell;
# each git worktree derives its own non-colliding ports and isolated state.
#
# ⚠️ KEEP IN SYNC across all toolchain sources — bump together:
#   - this file                       (beam.packages.erlang_28 + rust 1.96.0)
#   - .github/workflows/ci.yml        (ELIXIR_VERSION / OTP_VERSION / FLUTTER_VERSION + rust-toolchain)
#   - Dockerfile                      (production image base — FROM elixir:1.19-otp-28)
# If they drift, local devenv and CI compile under different toolchains and
# "green locally" stops predicting "green in CI".

let
  # Elixir 1.19 / OTP 28 built as a matched pair from one beam set. devenv's
  # languages.elixir only adds the elixir package — it does NOT pull a matching
  # OTP — so we pin erlang from the same erlang_28 binding to avoid the classic
  # mismatched-OTP-on-PATH footgun (KTD1).
  beam = pkgs.beam.packages.erlang_28;

  # ── Per-worktree deterministic ports (KTD5 / R8) ────────────────────────────
  # Hash the absolute worktree path (config.devenv.root, known at eval time) to a
  # stable 0..99 offset, then derive a 10-port window. Stable across restarts and
  # branch renames; changes only if the checkout physically moves. Overridable
  # per worktree via devenv.local.nix (see devenv.local.nix.example, R9).
  hexMap = {
    "0" = 0; "1" = 1; "2" = 2; "3" = 3; "4" = 4; "5" = 5; "6" = 6; "7" = 7;
    "8" = 8; "9" = 9; "a" = 10; "b" = 11; "c" = 12; "d" = 13; "e" = 14; "f" = 15;
  };
  hexToInt = s: lib.foldl' (acc: c: acc * 16 + hexMap.${c}) 0 (lib.stringToCharacters s);
  digest = builtins.substring 0 8 (builtins.hashString "sha256" config.devenv.root);
  raw = hexToInt digest;
  offset = raw - (raw / 100) * 100;
  portBase = 4000 + offset * 10;
  phxPort = portBase;
  p2pPort = portBase + 1;
  pgPort = portBase + 2;
  flutterPort = portBase + 3;

  # ── Shared caches outside any worktree (KTD4 / R11) ─────────────────────────
  # Immutable/derived downloads are shared so a second worktree's first run
  # reuses the first's; mutable state (pg data, _build, mydia_dev.db) stays
  # per-worktree under .devenv/ automatically.
  sharedCache = "${builtins.getEnv "HOME"}/.cache/mydia-devenv";

  # ── Postgres gating (R4) ────────────────────────────────────────────────────
  # SQLite is the default and needs no service. Postgres only matters under
  # DATABASE_TYPE=postgres; gate on the eval-time env so SQLite worktrees never
  # start a Postgres process.
  dbType = builtins.getEnv "DATABASE_TYPE";
  usePostgres = dbType == "postgres" || dbType == "postgresql";
in
{
  languages.elixir = {
    enable = true;
    package = beam.elixir_1_19;
  };

  languages.erlang = {
    enable = true;
    package = pkgs.erlang_28;
  };

  # Rust pinned to 1.96.0 to match CI (dtolnay/rust-toolchain@1.96.0) and the
  # retired Dockerfile.dev (--default-toolchain 1.96.0); only the old flake
  # floated on stable.latest (KTD2). `components` replaces (not appends) the
  # defaults, so rustc/cargo are restated alongside the lint/analysis tools.
  languages.rust = {
    enable = true;
    channel = "stable";
    version = "1.96.0";
    targets = [ "wasm32-unknown-unknown" "wasm32-wasip2" ];
    components = [ "rustc" "cargo" "clippy" "rustfmt" "rust-analyzer" "rust-src" ];
  };

  # Remaining dev toolchain. Flutter comes from nixpkgs (KTD3): player/flake.nix
  # already builds against pkgs.flutter, so the NixOS dynamic-linker/patchelf
  # handling is proven for this codebase. wasm-tools is carried from the flake's
  # shells (used by scripts/check-plugins.sh).
  packages = with pkgs; [
    flutter

    # Node.js for assets
    nodejs

    # Database CLI (SQLite is the default adapter)
    sqlite

    # Media processing
    ffmpeg

    # Build tools for NIFs (bcrypt_elixir, argon2_elixir, membrane, exqlite)
    gcc
    gnumake
    pkg-config

    # File watching (live reload)
    inotify-tools

    # Browser testing with Wallaby
    chromium
    chromedriver

    # deps + general utilities
    git
    curl

    # Inspect/validate WASM components (WIT plugin guests)
    wasm-tools
  ];

  env = {
    # Locale for Elixir (mirrors the retired default devShell).
    LANG = "C.UTF-8";
    LC_ALL = "C.UTF-8";

    # IEx shell history.
    ERL_AFLAGS = "-kernel shell_history enabled";

    # Wallaby browser tests.
    CHROME_PATH = "${pkgs.chromium}/bin/chromium";
    CHROMEDRIVER_PATH = "${pkgs.chromedriver}/bin/chromedriver";

    # Shared, worktree-independent caches (KTD4 / R11).
    MIX_HOME = "${sharedCache}/mix";
    HEX_HOME = "${sharedCache}/hex";
    PUB_CACHE = "${sharedCache}/pub-cache";
    NPM_CONFIG_CACHE = "${sharedCache}/npm";

    # Per-worktree ports (R8). lib.mkDefault so devenv.local.nix can pin them (R9).
    PORT = lib.mkDefault (toString phxPort);
    P2P_BIND_PORT = lib.mkDefault (toString p2pPort);
    FLUTTER_DEV_PORT = lib.mkDefault (toString flutterPort);

    # Postgres connection details (read by config/dev.exs only under
    # DATABASE_TYPE=postgres). devenv's Postgres bootstraps a superuser role
    # named after the OS user with trust auth, so we connect as $USER.
    DATABASE_HOST = "127.0.0.1";
    DATABASE_PORT = lib.mkDefault (toString pgPort);
    DATABASE_USER = lib.mkDefault (builtins.getEnv "USER");
  };

  # ── Postgres service (R4) ───────────────────────────────────────────────────
  # Data dir lives under the per-worktree .devenv/state/postgres automatically.
  # NOTE: initialDatabases only runs on first init — to change it later, delete
  # .devenv/state/postgres (documented in docs/development/setup.md).
  services.postgres = lib.mkIf usePostgres {
    enable = true;
    listen_addresses = "127.0.0.1";
    port = pgPort;
    initialDatabases = [ { name = "mydia_dev"; } { name = "mydia_test"; } ];
  };

  # ── Long-running processes (R5) ─────────────────────────────────────────────
  processes.phoenix.exec = "mix phx.server";

  # build_runner watch performs GraphQL/Riverpod codegen for the player. This is
  # distinct from MydiaWeb.FlutterWatcher (config/dev.exs), which runs
  # `flutter build web` on source changes — codegen feeds the web build, so both
  # are needed and they do not double-run.
  processes.flutter-codegen.exec =
    "cd player && flutter pub run build_runner watch --delete-conflicting-outputs";

  # ── First-run / re-entry setup tasks (R6) ───────────────────────────────────
  # Replace docker-entrypoint.sh. Guarded with execIfModified so re-entry is
  # fast: a task only runs when its declared inputs change. The exqlite NIF
  # platform-compat workaround is intentionally NOT ported — one native
  # toolchain compiles exqlite once and keeps it valid (R6).
  tasks = {
    "mydia:hex" = {
      exec = "mix local.hex --force --if-missing && mix local.rebar --force --if-missing";
      before = [ "devenv:enterShell" ];
      # Cheap no-op once installed into the shared MIX_HOME.
      execIfModified = [ "mix.exs" ];
    };

    "mydia:deps" = {
      exec = "mix deps.get";
      execIfModified = [ "mix.exs" "mix.lock" ];
      before = [ "devenv:enterShell" ];
      after = [ "mydia:hex" ];
    };

    "mydia:ecto" = {
      exec = "mix ecto.create --quiet && mix ecto.migrate";
      # Re-run when a migration is added/changed (idempotent otherwise).
      execIfModified = [ "priv/repo/migrations" ];
      before = [ "devenv:enterShell" ];
      after = [ "mydia:deps" ] ++ lib.optional usePostgres "devenv:processes:postgres@ready";
    };

    "mydia:assets" = {
      # assets.setup fetches the standalone tailwind/esbuild binaries; the npm
      # packages (daisyui, alpinejs, …) that @plugin/@import resolve against must
      # be installed separately or CSS rebuilds silently fail.
      exec = "mix assets.setup && cd assets && npm install";
      execIfModified = [ "assets/package.json" "assets/package-lock.json" ];
      before = [ "devenv:enterShell" ];
      after = [ "mydia:deps" ];
    };

    "mydia:flutter" = {
      exec = "cd player && flutter pub get";
      execIfModified = [ "player/pubspec.yaml" "player/pubspec.lock" ];
      before = [ "devenv:enterShell" ];
    };
  };

  # ── Git hooks (KTD7 / R17) ──────────────────────────────────────────────────
  # devenv owns the generated .pre-commit-config.yaml (git-ignored). Hooks run
  # inside this shell, so cargo/mix/dart resolve to the pinned toolchain — no
  # `nix develop .#rust -c …` subshell needed. Patterns mirror the retired
  # .pre-commit-config.yaml.
  git-hooks.hooks = {
    cargo-fmt = {
      enable = true;
      name = "cargo fmt";
      entry = "cargo fmt --manifest-path native/mydia_p2p/Cargo.toml -- --check";
      files = "^native/.*\\.rs$";
      pass_filenames = false;
    };
    cargo-clippy = {
      enable = true;
      name = "cargo clippy";
      entry = "cargo clippy --manifest-path native/mydia_p2p/Cargo.toml -- -D warnings";
      files = "^native/.*\\.rs$";
      pass_filenames = false;
    };
    plugins-check = {
      enable = true;
      name = "cargo fmt + clippy (wasm plugins)";
      entry = "scripts/check-plugins.sh";
      files = "^plugins/.*\\.rs$";
      pass_filenames = false;
    };
    mix-format = {
      enable = true;
      name = "mix format";
      entry = "mix format --check-formatted";
      files = "\\.(ex|exs|heex)$";
      pass_filenames = false;
    };
    dart-format = {
      enable = true;
      name = "dart format";
      entry = "dart format --set-exit-if-changed --line-length 80";
      files = "\\.dart$";
      excludes = [ "\\.(g|freezed)\\.dart$" ];
    };
    dart-analyze = {
      enable = true;
      name = "dart analyze";
      entry = "dart analyze --fatal-warnings";
      files = "\\.dart$";
      excludes = [ "\\.(g|freezed)\\.dart$" ];
      pass_filenames = false;
    };
  };

  # ── Shell-entry banner (R10) ────────────────────────────────────────────────
  enterShell = ''
    echo ""
    echo "Mydia dev environment (devenv) — $DEVENV_ROOT"
    echo "  Phoenix:   http://localhost:$PORT"
    echo "  P2P bind:  $P2P_BIND_PORT"
    echo "  Flutter:   dev-server port $FLUTTER_DEV_PORT"
    ${lib.optionalString usePostgres ''
      echo "  Postgres:  127.0.0.1:$DATABASE_PORT (mydia_dev / mydia_test)"''}
    echo "  Toolchain: Elixir $(elixir --version | tail -1 | cut -d' ' -f2) · Rust $(rustc --version | cut -d' ' -f2) · Node $(node --version)"
    echo ""
  '';
}
