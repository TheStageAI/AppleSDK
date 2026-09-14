# Crash-durable on-device stack — guarantees contract

This document is the public contract for the Apple SDK durability work.
It is generated from the typed error surface (`ModelLoadFailure`,
`FailureClassification`, `RepairLadder`) so the handling recipe cannot
drift from the code.

## Guarantees

| Id | Promise |
|---|---|
| **G1** | The SDK never aborts the host app. Recoverable conditions throw or degrade. |
| **G2** | A crash never costs work still on disk. Intact artifacts are not recompiled, re-downloaded, or re-decrypted. |
| **G3** | Good cache is never deleted on a failure that is not proven durable. |
| **G4** | One model's failure never takes down the others. The voice agent starts degraded when VAD+STT load. |
| **G5** | A torn write is never committed as valid. Extract uses stage-verify-commit; download lands in `.new` then replaces. |
| **G6** | Failures are attributable: handle, phase, classification. A memory kill is reported by the launch sentinel. |
| **G7** | Warm start does not regress. Full CRC / manifest verify runs only after an unclean exit. |

## Non-guarantees

- Thermal throttling and sustained-session power behavior.
- Model quality.
- Text-normaliser and tokenizer abort sites (static table construction; triaged after the model/pipeline/voice-agent guard).
- Verification of a bundle the SDK cannot verify (zero CRC, opaque etag, manifest-less legacy tree). Those degrade to a weaker check and are recorded as unverified — they are **never rejected**.
- Zip reclamation on a sidecar whose etag is empty. The zip is kept so a size-fallback stamp cannot force a re-download.

## Compatibility

No bundle regeneration. Every engine already shipped on Hugging Face at
its current `ModelRevisionMap` revision must load unchanged, including
on devices that already have an extracted tree.

New strictness (`verify_enforce`, `admission_enforce`, `zip_reclaim`)
stays **off** until the G0 compatibility matrix is green. `degraded_start`
defaults **on**. Hosts can flip all four via `UserDefaults` /
`TheStageAI.set_durability_flag` without a new build.

Existing extracted trees are **usable but unverified**. The SDK never
re-downloads just to obtain a manifest.

## Kill switches

| Flag | Default | UserDefaults key |
|---|---|---|
| `degraded_start` | on | `thestage.durability.degraded_start` |
| `admission_enforce` | off | `thestage.durability.admission_enforce` |
| `zip_reclaim` | on | `thestage.durability.zip_reclaim` |
| `verify_enforce` | off | `thestage.durability.verify_enforce` |
| `ane_ticket_restore` | on | `thestage.durability.ane_ticket_restore` |

`ane_ticket_restore` also reads process env
`THESTAGE_ANE_TICKET_RESTORE` (`0`/`1`/`off`/`on`). Env wins. Set it
in the Xcode scheme to A/B an app update: `=0` leaves `e5bundlecache`
empty (cold specialize); `=1` (default) plants saved tickets from
`Application Support/Qlip.SDK/ane_e5/`. Snapshot after a successful
load is always on. Change the flag **before** `TheStageAI.start` /
process launch — it is applied once per process.

## Per-classification handling recipe

`ModelLoadFailure.classification` is the decision key. Handle, phase, and
classification travel in the clear; the cause is redacted; no filesystem
paths cross into Dart (`PlatformException.details`).

| Classification | Typical cause | App response |
|---|---|---|
| `transient` | `missingFunctions`, ANE / jetsam during specialize | Retry once after releasing non-essential models. **Do not** wipe cache. Offer a smaller model if the retry fails. |
| `recoverable` | allocation failure, torn sidecar, `model.mil` zeroed | Typed error. Restore from the sealed blob if present, otherwise cold re-decrypt. Never abort. |
| `durable` | CRC / size mismatch vs `.tree_manifest.json` | Call `repair_model_cache(key)` for **that** model only, then reload. |
| `unknown` | Keychain / Secure Enclave unreadable, disk full, admission refuse | Retry after unlock; or prompt to free `needed_bytes`; or load a smaller model. **Never delete** the tree. |

`RepairLadder.action(classification:evidence:)` is the single decision
point. It advances only on proven-durable evidence:

| Evidence | Action |
|---|---|
| vault unreadable | `retryOnce` |
| manifest mismatch | `reextractTree` |
| `model.mil` zeroed, blob present | `restoreBlob` |
| `model.mil` zeroed, blob missing | `coldDecrypt` |
| classification `transient` | `retryOnce` |
| classification `durable` | `reextractTree` |
| anything else | `report` |

## Public surface

Swift (`TheStageAI`):

- `list_model_cache()` / `verify_model_cache(key:)` / `repair_model_cache(key:)` / `repair_all_model_cache()`
- `previous_launch` — last-run verdict (`cleanExit` / `selfAbort` / `likelyMemoryKill` / `crash` / `firstLaunch`)
- `field_counters` — recompiles, cache deletions, self-aborts, degraded starts, repair escalations, admission refusals
- `durability_flags` / `set_durability_flag(_:value:)`

Flutter (`TheStageFlutterSDK`) mirrors the same methods. Voice-agent
`start()` returns a capabilities snapshot (`listening` / `transcribing` /
`responding` / `speaking` + `reasons`). Set `require_full_stack: true`
(or `TSAgentConfig.require_full_stack`) to keep the old
all-or-nothing behavior.

Repair is scoped to Application Support `(SDK internals)`.
It never touches licensing, the offline counter, the validation cache, or
device-identity Keychain items.

## Field counters

A non-zero `cacheDeletions` or `selfAborts` count in a canary population
is a regression signal against G1 / G3.

## Rollout order

Stop aborting → make failures legible → stop destroying cache → isolate
node failures → see the crash → extract/download verify in observe-only
mode → **G0 gate** → enable verification enforcement → admission /
transient retry → zip reclamation last.
