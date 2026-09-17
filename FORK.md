# eggomi fork of `matrix-sdk-crypto-wasm`

Fork of [matrix-org/matrix-sdk-crypto-wasm](https://github.com/matrix-org/matrix-sdk-crypto-wasm),
Apache-2.0. Upstream `LICENSE` and all copyright headers are unchanged. This
file is the statement of changes required by Apache-2.0 §4(b).

Base: upstream tag **v18.8.0**.

## What is changed, and why

Two behavioural changes, both in `matrix-sdk-crypto` rather than in this repo —
see the companion fork [tzarebczan/matrix-rust-sdk](https://github.com/tzarebczan/matrix-rust-sdk),
branch `eggomi/sender-data-recalc-cache`.

### 1. Sender data is not recalculated per decrypted event

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

### 2. The Olm account is not re-pickled on read-only transactions

`StoreTransaction::account()` takes the account out of the store cache, so a
caller that only reads it leaves `PendingChanges::account` populated and is
indistinguishable from one that wrote. `commit` then pays twice: `deep_clone`,
which is `from_pickle(pickle())`, and the store write. Unpickling is the
expensive half — vodozemac rebuilds `key_ids_by_key` by deriving the public half
of every stored one-time key, one Curve25519 base multiplication each
(`src/olm/account/one_time_keys.rs`, `impl From<OneTimeKeysPickle>`).

`PendingChanges` carries nothing but the account, so when it is unchanged the
whole commit is a no-op. Measured on eggomi's web client: **1.09 s** across 61
commits in one 45-second boot trace, ~11 ms apiece, 19% of all main-thread time,
plus 61 redundant IndexedDB writes. The common trigger is benign — every /sync
calls `update_key_counts`, and a server reporting an unchanged one-time key count
leaves the account byte-for-byte identical.

The fix fingerprints the account when the transaction takes it and compares at
commit. It compares the whole pickle rather than tracking a dirty flag on each
mutating method, so a mutation nobody remembered to flag still changes the bytes
and the worst a miss can do is write when it need not have. That matters most
for a change with no other outward sign: receiving an Olm pre-key message
consumes an already-published one-time key, moving neither the uploaded count
nor the unpublished-key map.

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
  the name section) and must be absent from upstream's build. It is the marker
  for change 1; change 2 carries no such symbol of its own — both land together
  because `[patch]` pins one revision, which is what that check establishes.
- `npx jest` runs upstream's own suite against the built artifact.

## Upgrading

Upstream releases pair a `matrix-sdk-crypto-wasm` tag with one `matrix-rust-sdk`
revision (read it out of that tag's `Cargo.lock`). Rebase the fork branch onto
**that** revision rather than onto `main`, so the pairing stays the one upstream
tested, then rebuild and re-verify as above.
