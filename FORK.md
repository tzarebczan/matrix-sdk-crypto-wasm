# eggomi fork of `matrix-sdk-crypto-wasm`

Fork of [matrix-org/matrix-sdk-crypto-wasm](https://github.com/matrix-org/matrix-sdk-crypto-wasm),
Apache-2.0. Upstream `LICENSE` and all copyright headers are unchanged. This
file is the statement of changes required by Apache-2.0 §4(b).

Base: upstream tag **v18.8.0**.

## What is changed, and why

One behavioural change, in `matrix-sdk-crypto` rather than in this repo — see
the companion fork [tzarebczan/matrix-rust-sdk](https://github.com/tzarebczan/matrix-rust-sdk),
branch `eggomi/sender-data-recalc-cache`.

`OlmMachine::get_or_update_sender_data` recalculates a session's `SenderData`
whenever `should_recalculate()` is true, and only persists the result when it
raises the trust level. When it does not raise it, nothing is written, so
`should_recalculate()` stays true and the next event on the same session runs
`SenderDataFinder` again. For a sender whose trust can never be raised from the
store — an unsigned device, which is what every bridge ghost looks like — that
is a `get_user_devices` plus identity reads per decrypted event, for ever.

Measured on eggomi's web client backfilling bridged rooms: **2.18 s** under
`decrypt_room_event_inner` in a single boot, of which 1.07 s was IndexedDB
`get` and 0.57 s `getAll` — all of it recomputing the same answer.

The fix is not a TTL. `SenderDataFinder` reads exactly two things that can
change (stored device data, stored identities); both now move a generation
counter on `CryptoStoreWrapper`, so a `(session, claimed sender)` pair already
tried at the current generation provably cannot produce a different answer.

Upstream was checked first: no equivalent fix exists on `main`.

## Changes in *this* repo

- `Cargo.toml`: `[patch]` all four `matrix-rust-sdk` crates to the fork above,
  pinned by revision (not branch, so the build is reproducible).
- `pkg/` is committed. Upstream ignores it and publishes to npm from CI; this
  fork is consumed straight from git, so the build output is the delivery.
- `package.json`: the `prepack` script (`pnpm build && pnpm run test`) is
  removed. Package managers run lifecycle scripts when installing a dependency
  from git, and that one compiles Rust — it would break `pnpm install` on any
  machine without the toolchain. Use `pnpm build:fork` to rebuild deliberately.

## Rebuilding

Needs the Rust toolchain, the `wasm32-unknown-unknown` target, and `wasm-pack`.
The `[patch]` points at a private repo, so cargo needs git credentials:

```sh
export CARGO_NET_GIT_FETCH_WITH_CLI=true
pnpm build:fork
npx babel pkg/matrix_sdk_crypto_wasm_bg.js --out-dir pkg \
  --out-file-extension .cjs --plugins @babel/plugin-transform-modules-commonjs
```

Then verify the artifact rather than trusting the build log:

- `pkg/matrix_sdk_crypto_wasm_bg.js`, `.cjs` and both `.d.ts` should match
  upstream's published sizes exactly — only the `.wasm` should differ.
- The string `device_generation` must appear in `pkg/matrix_sdk_crypto_wasm_bg.wasm`
  (it is `#[inline(never)]` in the fork precisely so the symbol survives into
  the name section) and must be absent from upstream's build.
- `npx jest` runs upstream's own suite against the built artifact.

## Upgrading

Upstream releases pair a `matrix-sdk-crypto-wasm` tag with one `matrix-rust-sdk`
revision (read it out of that tag's `Cargo.lock`). Rebase the fork branch onto
**that** revision rather than onto `main`, so the pairing stays the one upstream
tested, then rebuild and re-verify as above.
