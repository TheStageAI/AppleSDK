@preconcurrency import Flutter
import Foundation
import TheStageCore

// --------------------------------------------------------------------------------------
// TTSStreamHandler
// --------------------------------------------------------------------------------------
@MainActor
final class TTSStreamHandler: NSObject, FlutterStreamHandler {

    // ----------------------------------------------------------------------------------
    // Private Attributes
    // ----------------------------------------------------------------------------------
    private var __event_sink: FlutterEventSink?
    private var __tasks: [String: Task<Void, Never>] = [:]
    private var __streamers: [String: TTSStreamer] = [:]

    // ----------------------------------------------------------------------------------
    // FlutterStreamHandler
    // ----------------------------------------------------------------------------------
    func onListen(
        withArguments arguments: Any?,
        eventSink events: @escaping FlutterEventSink
    ) -> FlutterError? {
        self.__event_sink = events
        return nil
    }

    func onCancel(
        withArguments arguments: Any?
    ) -> FlutterError? {
        for task in __tasks.values { task.cancel() }
        __tasks.removeAll()
        for streamer in __streamers.values { streamer.stop_stream() }
        __streamers.removeAll()
        __event_sink = nil
        return nil
    }

    // ----------------------------------------------------------------------------------
    // Public Methods
    // ----------------------------------------------------------------------------------
    var has_sink: Bool { __event_sink != nil }

    /// Begin a TTS stream. When `input_json["text"]` is empty the
    /// handler runs in push mode (Dart drives `send` / `finish_stream`);
    /// otherwise it runs as a one-shot inference.
    func start(
        stream_id: String,
        model_name: String,
        input_json: [String: Any]
    ) {
        __tasks[stream_id]?.cancel()
        __tasks[stream_id] = nil
        __streamers[stream_id]?.stop_stream()
        __streamers[stream_id] = nil

        guard let events = __event_sink else { return }

        let text = (input_json["text"] as? String) ?? ""
        let stream_config = __parse_tts_stream_config(
            input_json["stream_config"] as? [String: Any]
        )

        if text.isEmpty {
            __start_push(
                stream_id: stream_id,
                model_name: model_name,
                input_json: input_json,
                stream_config: stream_config,
                events: events
            )
        } else {
            __start_one_shot(
                stream_id: stream_id,
                model_name: model_name,
                input_json: input_json,
                events: events
            )
        }
    }

    func send(stream_id: String, text: String) {
        __streamers[stream_id]?.send(text)
    }

    func finish_stream(stream_id: String) {
        __streamers[stream_id]?.stop_stream()
    }

    func cancel(stream_id: String) {
        __tasks[stream_id]?.cancel()
        __tasks[stream_id] = nil
        __streamers[stream_id]?.stop_stream()
        __streamers[stream_id] = nil
        guard let events = __event_sink else { return }
        events([
            "stream_id": stream_id,
            "kind": "cancelled",
            "index": -1,
            "is_final": true,
        ])
    }

    // ----------------------------------------------------------------------------------
    // Private Methods
    // ----------------------------------------------------------------------------------
    private func __start_one_shot(
        stream_id: String,
        model_name: String,
        input_json: [String: Any],
        events: @escaping FlutterEventSink
    ) {
        do {
            let stream = try TheStageAI.shared.infer_stream(
                model_name: model_name,
                input_json: input_json
            )
            __tasks[stream_id] = Task.detached { [weak self] in
                await Self.__drain(
                    stream_id: stream_id,
                    stream: stream,
                    events: events,
                    on_complete: { [weak self] in
                        self?.__tasks[stream_id] = nil
                    }
                )
            }
        } catch {
            events(FlutterError(
                code: "THESTAGE_STREAM_ERROR",
                message: __sanitize_error(error),
                details: nil
            ))
        }
    }

    private func __start_push(
        stream_id: String,
        model_name: String,
        input_json: [String: Any],
        stream_config: TTSStreamConfig,
        events: @escaping FlutterEventSink
    ) {
        let generation = __parse_tts_generation_config(input_json)
        do {
            let streamer = try TheStageAI.shared.open_tts_streamer(
                model_name: model_name,
                generation: generation,
                config: stream_config
            )
            __streamers[stream_id] = streamer
            let output = streamer.output
            __tasks[stream_id] = Task.detached { [weak self] in
                await Self.__drain(
                    stream_id: stream_id,
                    stream: output,
                    events: events,
                    on_complete: { [weak self] in
                        self?.__tasks[stream_id] = nil
                        self?.__streamers[stream_id] = nil
                    }
                )
            }
        } catch {
            events(FlutterError(
                code: "THESTAGE_STREAM_ERROR",
                message: __sanitize_error(error),
                details: nil
            ))
        }
    }

    private nonisolated static func __drain(
        stream_id: String,
        stream: AsyncStream<InferenceStreamChunk>,
        events: @escaping FlutterEventSink,
        on_complete: @escaping @MainActor () -> Void
    ) async {
        var saw_final = false
        for await chunk in stream {
            guard !Task.isCancelled else { return }
            let event = __make_event(chunk, stream_id: stream_id)
            DispatchQueue.main.async {
                events(event)
            }
            if chunk.is_final {
                saw_final = true
                DispatchQueue.main.async { on_complete() }
            }
        }
        if !saw_final {
            let terminal: [String: Any] = [
                "stream_id": stream_id,
                "kind": "audio",
                "index": -1,
                "is_final": true,
            ]
            DispatchQueue.main.async {
                events(terminal)
                on_complete()
            }
        }
    }

    private nonisolated static func __make_event(
        _ chunk: InferenceStreamChunk,
        stream_id: String
    ) -> [String: Any] {
        var event: [String: Any] = [
            "stream_id": stream_id,
            "kind": chunk.kind,
            "index": chunk.index,
            "is_final": chunk.is_final,
        ]
        if let delta = chunk.delta { event["delta"] = delta }
        if let audio = chunk.audio {
            let data = audio.withUnsafeBufferPointer {
                Data(buffer: $0)
            }
            event["audio"] = FlutterStandardTypedData(
                float32: data
            )
        }
        if let sr = chunk.sample_rate {
            event["sample_rate"] = sr
        }
        if let v = chunk.time_to_first_token {
            event["time_to_first_token"] = v
        }
        if let v = chunk.prompt_tokens {
            event["prompt_tokens"] = v
        }
        if let v = chunk.generated_tokens {
            event["generated_tokens"] = v
        }
        if let v = chunk.tokens_per_second {
            event["tokens_per_second"] = v
        }
        if let v = chunk.total_seconds {
            event["total_seconds"] = v
        }
        return event
    }
}
