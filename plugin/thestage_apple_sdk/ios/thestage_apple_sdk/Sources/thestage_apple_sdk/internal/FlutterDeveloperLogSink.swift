@preconcurrency import Flutter
import Foundation
import TheStageCore

// --------------------------------------------------------------------------------------
// FlutterDeveloperLogSink
// --------------------------------------------------------------------------------------
/// Forwards non-Security ``TheStageLog`` events to a Flutter
/// ``EventChannel`` so `flutter run` can ``debugPrint`` them.
/// Unified Logging alone is invisible in the Flutter console.
final class FlutterDeveloperLogSink: TheStageLogSink, @unchecked Sendable {
    private let __lock = NSLock()
    private var __event_sink: FlutterEventSink?

    func attach(_ sink: FlutterEventSink?) {
        __lock.lock()
        __event_sink = sink
        __lock.unlock()
    }

    func log(
        level: TheStageLogLevel,
        category: String,
        event: String,
        message: String
    ) {
        __lock.lock()
        let sink = __event_sink
        __lock.unlock()
        guard let sink else { return }
        let payload: [String: String] = [
            "level": level.label,
            "category": category,
            "event": event,
            "message": message,
        ]
        DispatchQueue.main.async {
            sink(payload)
        }
    }
}

// --------------------------------------------------------------------------------------
// LogStreamHandler
// --------------------------------------------------------------------------------------
final class LogStreamHandler: NSObject, FlutterStreamHandler {
    private let __sink: FlutterDeveloperLogSink

    init(sink: FlutterDeveloperLogSink) {
        __sink = sink
        super.init()
    }

    func onListen(
        withArguments arguments: Any?,
        eventSink events: @escaping FlutterEventSink
    ) -> FlutterError? {
        __sink.attach(events)
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        __sink.attach(nil)
        return nil
    }
}
