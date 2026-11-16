# Loading models

Every model goes through the same three steps before it answers: the
pack is downloaded, it is unpacked once on the device, and the Neural
Engine compiles it on its first load. The SDK does all three inside one
call, and lets you do each ahead of time: download several packs in
parallel while the user reads your onboarding, compile them while a
loading screen is up, and bring them back warm from a background task
when iOS has thrown the compiled programs away.

This page is the contract for that: what each step costs, which calls
are cheap reads, and the order that keeps a phone responsive.

> **Main features**
>
> - **One call for a set**: `load_models` downloads, unpacks, loads
>   and warms a list of models in order, with progress per model.
> - **Download ahead, in parallel**: `prefetch_engines` per pack, as
>   many at once as you like; nothing is loaded into memory.
> - **Compile ahead**: `respecialize_if_needed` loads a cold model
>   once, warms it and stops it, so the next start is a second.
> - **Cheap read**: `is_pack_resident` never writes, never downloads,
>   needs no `initialize`, and is safe to call from a view body.
> - **Health check**: `specialization_health` loads one tiny test
>   engine (milliseconds when warm) and tells you which models must
>   compile again; call it when the app comes to the foreground.
> - **Stays specialized**: the Neural Engine programs are saved outside
>   `Caches` and put back after a purge.
> - **Delete to free space**: `delete_model` removes every copy of a
>   downloaded model from the device; it refuses while the model is in use.

## In this page

Here we will cover the following topics:

- [What a load costs](#what-a-load-costs): the three steps, where each is cached, what survives.
- [Quick start](#quick-start): a known set of models, ready in one call.
- [Download ahead, in parallel](#download-ahead-in-parallel): prefetch every pack at once, show "downloaded" without loading.
- [Compile ahead](#compile-ahead): the first load is the compile; run it on your schedule, one model at a time.
- [Stay specialized](#stay-specialized): detect a purge, re-specialize on a charger.
- [Memory and residency](#memory-and-residency): starts are reference-counted; what is loaded right now.
- [Usage Guides](#usage-guides): first launch of a three-model app, a catalog screen, an overnight keeper.
- [Troubleshooting](#troubleshooting): symptom → cause → fix.
- [Delete a model](#delete-a-model): free the disk a downloaded model takes.
- [Cleanup](#cleanup): releasing models.

## What a load costs

| Step | What happens | Cost | Cached where, survives what |
|---|---|---|---|
| Download | the pack is fetched from Hugging Face into the SDK's folder under Application Support | network bound; 100 MB to 2 GB per pack | the pack, per repo and revision; survives relaunch and app updates; an interrupted transfer resumes within 30 minutes, after that it restarts |
| Unpack | the archive is extracted and promoted to one resident copy; the archive is deleted once the model opened | seconds; needs free disk of twice the archive | the resident tree; survives relaunch and app updates; never purged by iOS |
| Compile and specialize | CoreML compiles the engines and the Neural Engine builds its programs, on the first load of that pack | cold: tens of seconds for a small LLM, minutes for a large one; warm: about a second | the compiled engines under Application Support; the Neural Engine programs under `Caches`, which iOS purges under storage pressure. The SDK saves a copy of them after every load and puts it back after a purge |
| Warm-up | one prediction per engine, so the first user request pays nothing | about 150 ms per model when warm | the saved programs now cover every engine the model uses |

Two consequences shape everything below. Downloads are independent of
each other, so they can run in parallel. Compiles are not: a device has
one Neural Engine compiler, and two loads at once queue on it, so
compile one model at a time and never behind a load the user is
waiting for.

## Quick start

| You want | Who owns the model | Use |
|---|---|---|
| A known set of models ready, in order | the SDK, by handle | `load_models` |
| One model, with a pipeline object back | you hold the pipeline | `start_model` |
| The bytes on the device, nothing in memory | nobody yet | `prefetch_engines` |
| A model warm before the user asks for it | nobody afterwards | `respecialize_if_needed` |

### One call for a set

**Swift**

```swift
import TheStageSDK

let ai = TheStageAI.shared
try await ai.initialize(api_token: sdkToken, hf_token: hfToken)

let stack: [TSModelStartRequest] = [
    .init(handle: "stt", path: "TheStageAI/thewhisper-large-v3-turbo",
          model_type: "thestage_asr", eviction_priority: .PINNED),
    .init(handle: "llm", path: "TheStageAI/LFM2.5-350M",
          model_type: "thestage_llm"),
    .init(handle: "tts", path: "TheStageAI/Qwen3-TTS-12Hz-0.6B-Base",
          model_type: "thestage_tts", required: false),
]
let statuses = try await ai.load_models(stack) { progress in
    // progress.model is the handle; progress.phase is
    // .downloading / .extracting / .loading / .ready.
    // progress.fraction is the overall 0...1 for that model
    // (download ends at 0.70, extract at 0.85).
    // progress.phase_fraction is the current phase's own 0...1:
    // "Downloading 100%", then "Compiling 0%".
    // The last event is (model: "sequence", phase: .ready).
}
// Every handle now answers start_model at once; the first
// request costs no compilation.
```

**Flutter**

```dart
// Flutter has no load_models yet: start the models in order.
// Each start downloads, unpacks and compiles the pack the first
// time, and is a cache hit after that.
await TheStageFlutterSDK.initialize(api_token: sdkToken);
final sub = TheStageFlutterSDK.on_progress.listen((e) {
  // {model_name, phase, progress}
});
await TheStageFlutterSDK.start_model(
  model_name: 'stt',
  engines_path: 'TheStageAI/thewhisper-large-v3-turbo',
);
await TheStageFlutterSDK.start_model(
  model_name: 'llm',
  engines_path: 'TheStageAI/LFM2.5-350M',
);
await sub.cancel();
```

`TSModelStartRequest` is the `start_model` argument set plus two
flags (`required`, `warmup`):

| Field | Default | Meaning |
|---|---|---|
| `handle` | — | the name you start and stop the model by |
| `path` | — | Hugging Face repo (`TheStageAI/...`), a local folder, or a zip |
| `model_type` | `nil` | the pack to pick when a repo holds several (`thestage_asr`, `thestage_llm`, `thestage_tts`, ...) |
| `device` | `"npu"` | compute unit (`"npu"`, `"gpu"` or `"cpu"`) for an engine the pack does not place itself; engines the pack places keep their placement |
| `devices` | `nil` | per-engine override, engine name to `"npu"` / `"gpu"` / `"cpu"`; wins over the pack's placement, for benches and diagnosis |
| `config` | `nil` | the same `[String: Any]` family options `start_model` takes (for example `voice_id` for TTS) |
| `revision` | `nil` | a pin; `nil` takes the revision this SDK version ships with |
| `eviction_priority` | `.NORMAL` | `.PINNED` is never unloaded to make room for another model |
| `required` | `true` | a failed required model aborts the sequence; a non-required one is reported `failed` and the rest continue |
| `warmup` | `true` | run every engine once after loading, so the model is specialized before its first request |

What one call guarantees:

1. **One copy per pack on disk.** The archive is deleted once the model
   is ready; nothing is kept twice.
2. **No member of the set is unloaded to load the next.** Members load
   one after another, in the order given. A required model that fails
   stops the sequence and the call throws; a non-required one is
   reported `failed` and the next member loads.
3. **Loaded means specialized.** Warm-up runs every engine once, and the
   Neural Engine programs are saved so they survive a purge.
4. **Progress per model**, then one final `ready` for the sequence.

### Important API

| Purpose | Swift | Flutter |
|---|---|---|
| Get a set of models ready | `load_models(_:on_load_progress:)` | start them in order |
| Load one model | `start_model(_:model_name:engines_path:...)` | `start_model` |
| Download and unpack only | `prefetch_engines(repo_id:model_type:revision:config:on_load_progress:)` | `prefetch_engines` |
| Is the pack on this device? (read) | `TheStageAI.is_pack_resident(engines_path:revision:)` | — |
| State of the compiled programs | `specialization_health(for:)` | — |
| Compile cold models in the background | `respecialize_if_needed(_:)` | — |
| Save the compiled programs now | `snapshot_specialization()`, `specialization_tickets()` | — |
| What is loaded, and how much memory is left | `residency_report()`, `load_report()` | — |
| Release a model | `stop_model(model_name:force:)` | `stop_model` |
| Delete a downloaded model | `delete_model(engines_path:revision:)` | `delete_model` |

Pass your Hugging Face token once at `initialize`; the SDK sends it
only to the Hub and strips it on CDN redirects. Public packs download
without one, rate-limited.

## Download ahead, in parallel

`prefetch_engines` downloads and unpacks one pack and returns the
local folder. It loads nothing, so it costs no memory and no Neural
Engine time, and it is the call to make while the user is still on your
onboarding or settings screen.

**Swift**

```swift
let packs = [
    "TheStageAI/thewhisper-large-v3-turbo",
    "TheStageAI/LFM2.5-350M",
    "TheStageAI/Qwen3-TTS-12Hz-0.6B-Base",
]
try await withThrowingTaskGroup(of: Void.self) { group in
    for repo in packs {
        group.addTask {
            // Returns the local folder of the unpacked pack (String).
            _ = try await TheStageAI.shared.prefetch_engines(
                repo_id: repo,        // HF repo id, local folder or zip
                model_type: nil,      // only for repos with several packs
                revision: nil,        // nil: the revision this SDK ships with
                config: nil           // ["engines_file_name": ...] picks one pack file
            ) { p in
                // p.model is the repo; p.phase is .downloading,
                // then .extracting; p.phase_fraction is this
                // pack's own 0...1. No .loading / .ready here:
                // nothing is constructed.
            }
        }
    }
    try await group.waitForAll()
}
```

**Flutter**

```dart
final packs = [
  'TheStageAI/thewhisper-large-v3-turbo',
  'TheStageAI/LFM2.5-350M',
];
await Future.wait([
  for (final repo in packs)
    TheStageFlutterSDK.prefetch_engines(repo_id: repo),
]);
```

Rules the SDK keeps, so you do not have to:

- **One download per pack.** A second `prefetch_engines` of a pack
  already in flight waits for the first and returns the same folder;
  nothing downloads twice. Different packs run at the same time and
  unpack at the same time.
- **A pack is one unit.** Pass `model_type` only when the repo holds
  several packs (the speaker and VAD repos). With it, downloads of that
  type run one after another.
- **Disk is checked first.** Unpacking needs free space of twice the
  archive; otherwise the call throws `insufficientSpace` with the
  bytes needed, before any download.
- **Downloads are in-process.** They run while your app is in the
  foreground or holds a background mode of its own (audio, for
  instance). If iOS suspends the app, the transfer pauses and resumes
  from where it stopped on the next call within 30 minutes; later than
  that the Hub link has expired and the pack restarts from zero.
  `handleBackgroundURLSession` is kept for apps that still call it
  and does nothing.

### Show "downloaded" without loading

`is_pack_resident` answers whether the pack is already on this device.
It is a read: no network, no download, no file writes, no initialization
needed, so a catalog can call it for every row, and a timer can poll it
while a download runs.

```swift
let on_device = TheStageAI.is_pack_resident(
    engines_path: "TheStageAI/LFM2.5-350M"
)
```

> [!TIP]
> - Run two or three downloads at once, not ten: they share the
>   bandwidth, and a user who taps one model wants that one first.
> - Keep the screen awake during a download the user is waiting for;
>   the SDK does not hold a wake assertion.
> - A download does not need the SDK initialized to be *checked*
>   (`is_pack_resident`), but it needs `initialize` to *run*.

## Compile ahead

There is no separate compile call: the first load of a pack is the
compile, and it is what makes a cold start slow. Two calls let you pick
when it happens.

`load_models` is for the models you need now. It loads them in the
order given, warms each, and saves the Neural Engine programs; the user
sees one progress bar.

`respecialize_if_needed` is for models you want warm but not loaded.
It checks which of the requests are cold, loads only those, warms them,
saves the programs, and stops them again. Memory is back to where it was
when it returns; the next `start_model` of that pack takes about a
second.

```swift
// After the downloads above, while a "Preparing models" screen is up:
for request in stack {
    _ = try await TheStageAI.shared.respecialize_if_needed([request])
}
```

> [!TIP]
> - **One model at a time.** A device has one Neural Engine compiler.
>   Two compiles at once do not finish sooner, and a compile queued
>   behind one the user is waiting for makes that one slower.
> - **Never behind a user's load.** If a `start_model` is in flight,
>   wait for it before compiling anything else.
> - **Charger and screen.** A large LLM compiles for minutes on a
>   phone. Do it with the screen kept awake, or from a background task
>   that requires external power (next section).

## Stay specialized

iOS clears `Caches` under storage pressure, which throws away the
Neural Engine programs; the next start of every model would then
specialize for tens of seconds. The SDK saves those programs outside
`Caches` after every load, puts them back after a purge, and can tell
you before your user finds out.

```swift
let health = try await TheStageAI.shared.specialization_health(for: stack)
// .warm                    every requested model is proven and its programs are present
// .purged(restored: n)     the cache was wiped; n programs were put back
// .cold(models: [handles]) these models must specialize again

// From a BGProcessingTask (charger + idle), or after an app update:
_ = try await TheStageAI.shared.respecialize_if_needed([request])   // one model per task
```

`specialization_health` costs one tiny engine load (milliseconds when
warm). It needs `initialize`, writes that small engine to the SDK's
folder under Application Support on first use, and after a purge puts
the saved programs back before it answers, so call it when the app
comes to the foreground or from a background task, not from a view
body; `is_pack_resident` is the read for views. A purge is reported `.cold` for every requested model until a
load of that model proves the restored programs are ones CoreML
accepts; `respecialize_if_needed` is that proof.

Some models finish specializing on their first inference rather than on
load. After the first request of each model, call
`snapshot_specialization()` once; `specialization_tickets()` tells
you whether anything is still unsaved (`saved < live`).

A small app-side keeper is enough: check health when the app comes to
the foreground, at most hourly, and when it is not `.warm` submit a
`BGProcessingTaskRequest` with `requiresExternalPower = true` that
calls `respecialize_if_needed` for one model and resubmits itself while
models remain. Register the task's launch handler before the app
finishes launching; `BGTaskScheduler` aborts otherwise.

## Memory and residency

A running handle is held by owners. `start_model(..., owner:)` of a
handle that is already running shares the loaded model and adds that
owner; `stop_model(..., owner:)` removes it, and the model unloads when
no owner holds it, or at once with `force: true`. Two features that
share one model (dictation and a voice assistant both on `"stt"`) pass
different owners and do not lose it when the first one stops.

Starts without an owner share one hold, as before: starting a running
handle again changes nothing, and one `stop_model` unloads it. A start
with a different `config` (another TTS voice) reloads the model when no
other owner holds it, and throws `ModelNameConflict` when one does.

When memory is short the SDK unloads a `.NORMAL` model the sequence
does not need to make room; a `.PINNED` one is never unloaded for
memory. `residency_report()` lists what is loaded and by how many
owners; `load_report()` adds each model's footprint, the memory still
available and why the last load plan did what it did.

Where each engine runs is declared by the pack: model engines on the
Neural Engine, spectrogram front ends on the CPU. There is nothing to
configure; a `devices` entry naming one engine still overrides it, for
benches and diagnosis.

## Usage Guides

### First launch of a three-model app

> **Problem**
>
> **Building** — a voice assistant that needs ASR, an LLM and TTS
> before it can say hello.
>
> **Users want** — one progress bar that moves, and a first reply that
> does not stall.
>
> **Hard part** — three downloads are fast together and slow in turn;
> three compiles are the opposite.

**Solution — what to use**

- `prefetch_engines` for all three in a task group; show one bar from
  the sum of the three `phase_fraction` values.
- `load_models` for the three, in the order you will use them; show
  "Preparing" with its per-model progress.
- Keep the screen awake across both steps.

```swift
try await withThrowingTaskGroup(of: Void.self) { group in
    for request in stack {
        group.addTask {
            _ = try await TheStageAI.shared.prefetch_engines(
                repo_id: request.path, model_type: request.model_type
            ) { p in progress.update(request.handle, p.phase_fraction) }
        }
    }
    try await group.waitForAll()
}
_ = try await TheStageAI.shared.load_models(stack) { p in
    progress.update(p.model, p.phase_fraction)
}
```

> [!TIP]
> - Order the set by first use: the model the greeting needs goes
>   first.
> - A non-required model (`required: false`) failing to download
>   must not block the greeting; the app degrades and retries later.

### A catalog screen with download buttons

> **Problem**
>
> **Building** — a settings screen that lists every model with
> "Download", a progress ring, and "Downloaded".
>
> **Users want** — tap several, see each one move, see the state
> survive a relaunch.
>
> **Hard part** — the screen re-renders often; nothing it reads may
> cost a load or a write.

**Solution — what to use**

- `is_pack_resident` for the "Downloaded" state of every row; it is a
  read and safe in a view body.
- `prefetch_engines` per tap, with a per-row guard so a second tap
  while a download runs does nothing.
- No `start_model` from the catalog: loading belongs to the feature
  that uses the model.

```swift
func download(_ repo: String) {
    guard phase[repo] == nil, !TheStageAI.is_pack_resident(engines_path: repo)
    else { return }
    phase[repo] = "starting"
    Task {
        do {
            _ = try await TheStageAI.shared.prefetch_engines(repo_id: repo) { p in
                Task { @MainActor in
                    fraction[repo] = p.phase_fraction
                    phase[repo] = p.phase.rawValue
                }
            }
            phase[repo] = nil
        } catch {
            phase[repo] = error.localizedDescription
        }
    }
}
```

### Keep models warm overnight

> **Problem**
>
> **Building** — an app whose models must answer in a second, days
> after they were downloaded.
>
> **Users want** — no "compiling" after the phone ran low on space.
>
> **Hard part** — iOS purges the compiled programs silently, and a
> compile is minutes of Neural Engine time you do not want in the
> foreground.

**Solution — what to use**

- `specialization_health` on foreground, at most hourly.
- A `BGProcessingTask` with `requiresExternalPower = true` that
  calls `respecialize_if_needed` for one model and resubmits while
  models remain.
- Skip the task while a load of your own is in flight.

```swift
// At app init, before launch finishes:
BGTaskScheduler.shared.register(
    forTaskWithIdentifier: "ai.example.respecialize", using: nil
) { task in
    guard let task = task as? BGProcessingTask else { return }
    let work = Task { @MainActor in
        let health = try? await TheStageAI.shared.specialization_health(for: stack)
        let todo: [TSModelStartRequest]
        switch health {
        case .cold(let cold)?: todo = stack.filter { cold.contains($0.handle) }
        case .purged?: todo = stack
        default: todo = []
        }
        guard let first = todo.first else { return false }
        _ = try? await TheStageAI.shared.respecialize_if_needed([first])
        return todo.count > 1
    }
    task.expirationHandler = { work.cancel() }
    Task {
        let more = await work.value
        task.setTaskCompleted(success: !work.isCancelled)
        if more { schedule() }
    }
}

// On foreground, at most hourly:
if try await TheStageAI.shared.specialization_health(for: stack) != .warm {
    let request = BGProcessingTaskRequest(identifier: "ai.example.respecialize")
    request.requiresExternalPower = true
    try? BGTaskScheduler.shared.submit(request)
}
```

> [!TIP]
> - One model per task: a task that expires mid-compile wastes the
>   whole compile, and iOS budgets processing tasks in minutes.
> - The task handler must be registered before the app finishes
>   launching.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| First request after a launch takes tens of seconds | The Neural Engine programs were purged, or the model was never warmed. | `load_models` (warms) instead of a bare `start_model`; a keeper with `respecialize_if_needed`. |
| `specialization_health` stays `.cold` for a model that works | The model is loaded only through a direct constructor or `start_model` and was never proven since a purge. | Let `respecialize_if_needed` run once; it proves and saves. |
| A download restarts from zero after a relaunch | More than 30 minutes passed; the Hub link had expired. | Expected. Keep the app in the foreground or resume sooner. |
| `insufficientSpace` before any bytes download | Unpacking needs free disk of twice the archive. | Report `needed_bytes` to the user; nothing was downloaded. |
| Two models downloaded, one failed with `extractionFailed` | SDK older than 1.5.0: a concurrent unpack was swept as an orphan. | Update the SDK; retry the failed one. |
| A model fails to load while a settings screen is open | SDK older than 1.5.0: `is_pack_resident` touched the resident files while they were loading. | Update the SDK; the check is a read now. |
| Two features lose a shared model when one stops | Both started the same handle; `stop_model` with `force: true`. | Stop without `force`: the model unloads with the last user. |
| Compile of one model makes another's start slow | Both run on the one Neural Engine compiler. | Compile one at a time; never a background compile behind a user's load. |

## Delete a model

`delete_model` removes a downloaded model from the device and returns the
space it freed. Name the model the way you started or prefetched it: by
its repo id, the `engines_path` you pass to `start_model`.

**Swift**

```swift
let ai = TheStageAI.shared
_ = try? ai.stop_model(model_name: "tts")     // a loaded model is refused
let result = try await ai.delete_model(engines_path: "TheStageAI/phonon-31m-en")
print(result.freed_bytes)                      // 0 when nothing was there
```

**Flutter**

```dart
try {
  final result = await TheStageFlutterSDK.delete_model(
    engines_path: 'TheStageAI/phonon-31m-en',
  );
  print(result.freed_bytes);
} on ModelInUseException catch (e) {
  // stop each of e.model_names, then retry
} on ModelBusyException {
  // a download or start of it is running; retry once it finishes
}
```

**Python**

```python
result = await thestage_sdk.delete_model("TheStageAI/phonon-31m-en")
print(result.freed_bytes)
# a refusal raises SDKError with code "ModelInUse" or "ModelBusy"
```

- **Every copy goes.** Without `revision` the call removes all revisions
  on the device, including one an earlier SDK version downloaded, and the
  versions built for this device's Neural Engine. Pass a `revision` to
  remove only that one.
- **Stop it first.** While the model is loaded the call throws
  `ModelInUse` (with the model names that hold it) and removes nothing.
  A pipeline you constructed directly holds it until you release it.
- **Not during a download.** While a download, unpack or start of the
  model is in flight the call throws `ModelBusy`. A start that begins
  during a delete waits for it and then downloads again.
- **Safe to repeat.** A second call returns 0 bytes. A local folder or
  archive you passed as `engines_path` belongs to your app and is never
  deleted.
- **Mac apps without App Sandbox** share one model folder per user:
  deleting a model there removes it for the other such apps too, and they
  download it again on their next start.

## Cleanup

**Swift**

```swift
let ai = TheStageAI.shared
for request in stack {
    _ = try ai.stop_model(model_name: request.handle)
}
// A model unloads when its last start is stopped;
// force: true unloads it at once.
```

**Flutter**

```dart
await TheStageFlutterSDK.stop_model(model_name: 'stt');
await TheStageFlutterSDK.stop_model(model_name: 'llm');
```
