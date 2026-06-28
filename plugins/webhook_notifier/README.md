# webhook_notifier

The bundled Mydia webhook/Discord notifier plugin (U10) — the reference
implementation of the v1 WASM plugin ABI.

## Building

The `priv/plugins/webhook_notifier.wasm` artifact is **build-produced, not
committed**: it is gitignored (`/priv/plugins/*.wasm`) and the `:plugins` mix
compiler builds it from this crate's source on every `mix compile` (dev, test,
CI, and the Docker image build). Source under `plugins/*/` is the only truth —
there is nothing to re-copy or keep in sync by hand. Just run `mix compile`
after changing `src/lib.rs`.

To build the guest manually (e.g. to inspect the artifact):

```sh
rustup target add wasm32-wasip2   # once
cargo build --release --target wasm32-wasip2
```

The guest is a WebAssembly **component** built for `wasm32-wasip2` against the
canonical WIT contract — all egress is through the imported `mydia.http_request`
/ `mydia.data_read` host functions.

## Linting

The pre-commit hook runs `scripts/check-plugins.sh` (fmt + clippy against
`wasm32-unknown-unknown`) on any `plugins/**.rs` change, using the devenv
shell's pinned Rust toolchain (`languages.rust` in `devenv.nix`) rather than a
host rustup. Run it manually from inside the devenv shell:

```sh
devenv shell -- scripts/check-plugins.sh        # fmt --check + clippy -D warnings
devenv shell -- scripts/check-plugins.sh --fix  # rewrite formatting
```

(Without devenv, `scripts/check-plugins.sh` also works against a host rustup that
has the `wasm32-unknown-unknown` target installed.)

## ABI

- `mydia_alloc(len) -> ptr` — the host writes the event JSON here before calling `handle`.
- `handle(ptr, len) -> i64` — returns a packed `(out_ptr << 32) | out_len` pointing at a result JSON.
- Imports (`mydia` namespace): `http_request` and `data_read`, each
  `(req_ptr, req_len, resp_ptr, resp_cap) -> i32` returning the response length (or `< 0`).
