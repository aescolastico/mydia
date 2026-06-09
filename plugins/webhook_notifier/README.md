# webhook_notifier

The bundled Mydia webhook/Discord notifier plugin (U10) — the reference
implementation of the v1 WASM plugin ABI.

## Building

```sh
rustup target add wasm32-unknown-unknown   # once
cargo build --release --target wasm32-unknown-unknown
cp target/wasm32-unknown-unknown/release/webhook_notifier.wasm \
   ../../priv/plugins/webhook_notifier.wasm
```

The committed artifact at `priv/plugins/webhook_notifier.wasm` is what ships and
what the tests run against. Rebuild and re-copy it whenever `src/lib.rs` changes,
and keep it in sync in the same commit. The guest uses no WASI APIs (all egress
is through the imported `mydia.http_request` / `mydia.data_read` host functions),
so `wasm32-unknown-unknown` is sufficient — no `wasm32-wasip1` toolchain needed.

## Linting

The pre-commit hook runs `scripts/check-plugins.sh` (fmt + clippy against
`wasm32-unknown-unknown`) on any `plugins/**.rs` change, using the flake's
pinned Rust toolchain (`devShells.rust`) rather than a host rustup. Run it
manually with:

```sh
nix develop .#rust -c scripts/check-plugins.sh        # fmt --check + clippy -D warnings
nix develop .#rust -c scripts/check-plugins.sh --fix  # rewrite formatting
```

(Without nix, `scripts/check-plugins.sh` also works against a host rustup that
has the `wasm32-unknown-unknown` target installed.)

## ABI

- `mydia_alloc(len) -> ptr` — the host writes the event JSON here before calling `handle`.
- `handle(ptr, len) -> i64` — returns a packed `(out_ptr << 32) | out_len` pointing at a result JSON.
- Imports (`mydia` namespace): `http_request` and `data_read`, each
  `(req_ptr, req_len, resp_ptr, resp_cap) -> i32` returning the response length (or `< 0`).
