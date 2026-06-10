{ inputs, ... }:

{
  perSystem = { system, pkgs, ... }:
    let
      # Pinned Rust toolchain (via rust-overlay) for the native p2p NIF and the
      # wasm32 plugin guests. Used by the pre-commit hooks in place of a host
      # `rustup`: nix owns both the toolchain and its linker wrapper, so it can't
      # rot when a host rustup store path is garbage-collected.
      rustPkgs = import inputs.nixpkgs {
        inherit system;
        overlays = [ inputs.rust-overlay.overlays.default ];
      };
      rustToolchain = rustPkgs.rust-bin.stable.latest.default.override {
        extensions = [ "clippy" "rustfmt" "rust-src" ];
        # wasm32-unknown-unknown: legacy core-wasm plugin guests (being migrated).
        # wasm32-wasip2: component-model plugin guests (WIT). The wit-bindgen crate
        # is a cargo dependency, so no system binding-generator is needed; wasm-tools
        # (below) is for inspecting/validating the produced components.
        targets = [ "wasm32-unknown-unknown" "wasm32-wasip2" ];
      };
    in
    {
      # Lightweight shell holding just the Rust toolchain. The pre-commit hooks
      # invoke it via `nix develop .#rust -c ...` so commits never depend on a
      # host rust install.
      devShells.rust = pkgs.mkShell {
        buildInputs = [ rustToolchain pkgs.gcc pkgs.pkg-config pkgs.wasm-tools ];

        # Keep lint builds in their own target dir so they never collide with
        # the (sometimes root-owned) artifacts left by Docker/host builds, and
        # so nix's rustc doesn't thrash a target cache shared with another
        # toolchain. Covered by the `**/target/` gitignore rule.
        shellHook = ''
          export CARGO_TARGET_DIR="''${CARGO_TARGET_DIR:-$PWD/target/precommit}"
        '';
      };

      devShells.default = pkgs.mkShell {
        buildInputs = [
          # Rust toolchain (native p2p NIF + wasm32 plugin guests)
          rustToolchain

          # Inspect/validate WASM components (WIT plugin guests)
          pkgs.wasm-tools

          # Elixir/Erlang — pinned to Elixir 1.19 / OTP 28 (built as a matched
          # pair via beam.packages.erlang_28) to match the runtime environments.
          #
          # ⚠️ KEEP IN SYNC across all three toolchain sources — bump together:
          #   - this file (elixir_1_19 + erlang_28)
          #   - Dockerfile.dev            (FROM elixir:1.19-otp-28)
          #   - .github/workflows/ci.yml  (ELIXIR_VERSION / OTP_VERSION)
          # If they drift, local nix, Docker dev, and CI compile under different
          # toolchains and "green locally" stops predicting "green in CI"
          # (e.g. --warnings-as-errors and mix.lock resolution differ by version).
          pkgs.beam.packages.erlang_28.elixir_1_19
          pkgs.erlang_28

          # Node.js for assets (latest)
          pkgs.nodejs

          # Database
          pkgs.sqlite

          # Media processing
          pkgs.ffmpeg

          # Build tools for NIFs (bcrypt_elixir, argon2_elixir, membrane)
          pkgs.gcc
          pkgs.gnumake
          pkgs.pkg-config

          # File watching (for live reload)
          pkgs.inotify-tools

          # Browser testing with Wallaby
          pkgs.chromium
          pkgs.chromedriver

          # Git (needed for deps)
          pkgs.git

          # Useful development utilities
          pkgs.curl
        ];

        shellHook = ''
          # Configure Mix and Hex to use local directories
          export MIX_HOME="$PWD/.nix-mix"
          export HEX_HOME="$PWD/.nix-hex"
          export PATH="$MIX_HOME/bin:$HEX_HOME/bin:$PATH"

          # Enable IEx history
          export ERL_AFLAGS="-kernel shell_history enabled"

          # Configure locale for Elixir
          export LANG="C.UTF-8"
          export LC_ALL="C.UTF-8"

          # For Wallaby browser tests
          export CHROME_PATH="${pkgs.chromium}/bin/chromium"
          export CHROMEDRIVER_PATH="${pkgs.chromedriver}/bin/chromedriver"

          # Ensure hex and rebar are installed (only show output in interactive shells)
          if [ ! -d "$MIX_HOME" ]; then
            if [ -t 1 ]; then
              echo "Setting up Mix and Hex..."
              mix local.hex --force
              mix local.rebar --force
            else
              mix local.hex --force >/dev/null 2>&1
              mix local.rebar --force >/dev/null 2>&1
            fi
          fi

          # Only show welcome message in interactive shells
          if [ -t 1 ]; then
            echo ""
            echo "Mydia development environment loaded!"
            echo "  Elixir: $(elixir --version | head -n 1)"
            echo "  Erlang: $(erl -eval 'erlang:display(erlang:system_info(otp_release)), halt().' -noshell 2>&1)"
            echo "  Node.js: $(node --version)"
            echo ""
            echo "Run 'mix deps.get' to install dependencies"
            echo "Run 'mix phx.server' to start the development server"
            echo ""
          fi
        '';
      };
    };
}
