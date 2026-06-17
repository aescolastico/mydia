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
  };

  enterShell = ''
    echo ""
    echo "Mydia development environment (devenv) loaded!"
    echo "  Elixir:  $(elixir --version | tail -n 1)"
    echo "  Erlang:  $(erl -eval 'erlang:display(erlang:system_info(otp_release)), halt().' -noshell 2>&1)"
    echo "  Rust:    $(rustc --version)"
    echo "  Node.js: $(node --version)"
    echo "  Flutter: $(flutter --version 2>/dev/null | head -n 1)"
    echo ""
  '';
}
