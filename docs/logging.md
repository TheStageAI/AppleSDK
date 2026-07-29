# Logging & crash breadcrumbs

Optional developer logging and support blobs for the TheStage Apple SDK.
Security / encryption internals are never included in these surfaces.

## Session logfile + terminal

```swift
import TheStageSDK

let url = FileManager.default.temporaryDirectory
    .appendingPathComponent("thestage-session.log")
try TheStageAI.start_session_log(to: url, level: .debug, tee_console: true)
// … run …
let path = TheStageAI.end_session_log()
```

Or install sinks yourself:

```swift
TheStageAI.set_developer_log_sink(TheStagePrintLogSink())
TheStageAI.log_level = .debug
```

Also: `TheStageAI.configure_logging(...)` when you want a one-shot setup.

## Crash / support reports

```swift
let json = TheStageAI.user_breadcrumbs_json()
let text = await TheStageAI.debugReport()
```

Attach either blob to Crashlytics, Sentry, or a support ticket. Paths are
redacted; prompts and security details are omitted.

## Flutter

`TheStageFlutterSDK.initialize` prints SDK developer logs in `flutter run`
via the plugin log channel. Security / encryption internals are never included.

## Agent checklist

- Use session log / `debugReport` for support; never ask users for API tokens.
- Expect redacted paths; do not log prompts from app code into shared sinks
  unless the product requires it.
- Flutter: rely on plugin logs in debug; do not scrape encryption key material.
