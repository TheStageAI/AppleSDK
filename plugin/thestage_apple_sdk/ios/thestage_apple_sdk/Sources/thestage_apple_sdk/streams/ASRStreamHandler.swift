@preconcurrency import Flutter
import Foundation
import TheStageCore

// --------------------------------------------------------------------------------------
// ASRStreamHandler
// --------------------------------------------------------------------------------------
@MainActor
final class ASRStreamHandler {

    // ----------------------------------------------------------------------------------
    // Private Attributes
    // ----------------------------------------------------------------------------------
    private var __event_sink: FlutterEventSink?
    private var __streams: [String: ASRStream] = [:]
    private var __tasks: [String: Task<Void, Never>] = [:]

    // ----------------------------------------------------------------------------------
    // Public Methods
    // ----------------------------------------------------------------------------------
    func attach_sink(_ sink: FlutterEventSink?) {
        __event_sink = sink
    }

    func has(_ stream_id: String) -> Bool {
        __streams[stream_id] != nil
    }

    func start(
        stream_id: String,
        model_name: String,
        input_json: [String: Any]
    ) {
        cancel(stream_id: stream_id)
        guard let events = __event_sink else { return }
        __tasks[stream_id] = Task { [weak self] in
            guard let self else { return }
            do {
                let pipeline = try TheStageAI.shared.asr_pipeline(
                    model_name: model_name
                )
                let generation = self.__decode(
                    ASRGenerationConfig.self, from: input_json
                ) ?? ASRGenerationConfig()
                let streaming_json = input_json["streaming"] as? [String: Any]
                    ?? [:]
                let streaming = self.__decode(
                    ASRStreamingConfig.self, from: streaming_json
                ) ?? ASRStreamingConfig()
                var vad: (any VADAgent)?
                if let vad_name = input_json["vad_model_name"] as? String,
                   !vad_name.isEmpty
                {
                    vad = try TheStageAI.shared.asr_vad(
                        model_name: vad_name
                    )
                }
                let stream = try await ASREngine(
                    pipeline: pipeline, vad: vad
                ).open_stream(generation, streaming)
                self.__streams[stream_id] = stream
                await self.__drain(
                    stream_id: stream_id,
                    stream: stream,
                    events: events
                )
            } catch {
                events(FlutterError(
                    code: "THESTAGE_STREAM_ERROR",
                    message: error.localizedDescription,
                    details: nil
                ))
            }
        }
    }

    func send(stream_id: String, pcm: [Float]) {
        __streams[stream_id]?.send(pcm)
    }

    func flush(stream_id: String) {
        __streams[stream_id]?.flush()
    }

    func close(stream_id: String) async -> ASRResult {
        guard let stream = __streams[stream_id] else {
            return .empty
        }
        let result = await stream.close()
        __tasks[stream_id]?.cancel()
        __tasks[stream_id] = nil
        __streams[stream_id] = nil
        return result
    }

    func cancel(stream_id: String) {
        __tasks[stream_id]?.cancel()
        __tasks[stream_id] = nil
        __streams[stream_id]?.cancel()
        __streams[stream_id] = nil
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

    private func __drain(
        stream_id: String,
        stream: ASRStream,
        events: @escaping FlutterEventSink
    ) async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for await event in stream.events {
                    guard !Task.isCancelled else { return }
                    Self.__emit(
                        Self.__encode_event(event, stream_id: stream_id),
                        events
                    )
                }
            }
            group.addTask {
                for await text in stream.partials {
                    guard !Task.isCancelled else { return }
                    Self.__emit([
                        "stream_id": stream_id,
                        "kind": "partial",
                        "text": text,
                        "is_final": false,
                    ], events)
                }
            }
        }
    }

    private nonisolated static func __emit(
        _ payload: [String: Any],
        _ events: @escaping FlutterEventSink
    ) {
        DispatchQueue.main.async { events(payload) }
    }

    private nonisolated static func __encode_event(
        _ event: ASRStreamEvent,
        stream_id: String
    ) -> [String: Any] {
        switch event {
        case .BEGIN:
            return [
                "stream_id": stream_id,
                "kind": "begin",
                "is_final": false,
            ]
        case .TURN(let turn):
            return [
                "stream_id": stream_id,
                "kind": "turn",
                "transcript": turn.transcript,
                "committed": turn.committed,
                "hypothesis": turn.hypothesis,
                "end_of_turn": turn.end_of_turn,
                "is_final": turn.end_of_turn,
            ]
        case .TERMINATION(let audio_seconds, let metrics):
            var payload: [String: Any] = [
                "stream_id": stream_id,
                "kind": "termination",
                "audio_seconds": audio_seconds,
                "is_final": true,
            ]
            if let metrics {
                payload["metrics"] = [
                    "total_seconds": metrics.total_seconds,
                    "prefill_seconds": metrics.prefill_seconds,
                    "decode_seconds": metrics.decode_seconds,
                    "encode_seconds": metrics.encode_seconds,
                    "prompt_tokens": metrics.prompt_tokens,
                    "generated_tokens": metrics.generated_tokens,
                    "tokens_per_second": metrics.tokens_per_second,
                ]
            }
            return payload
        }
    }

    private nonisolated static func __encode_turn(
        _ turn: ASRTurn,
        stream_id: String
    ) -> [String: Any] {
        [
            "stream_id": stream_id,
            "kind": "turn",
            "transcript": turn.transcript,
            "committed": turn.committed,
            "hypothesis": turn.hypothesis,
            "end_of_turn": turn.end_of_turn,
            "is_final": turn.end_of_turn,
        ]
    }

    private nonisolated static func __result(_ turn: ASRTurn?) -> ASRResult {
        guard let turn else { return .empty }
        return ASRResult(
            text: turn.committed,
            tokens: nil,
            token_count: 0,
            decode_seconds: 0,
            metrics: .zero,
            words: turn.words,
            timestamp_mode: .WORD,
            language: turn.language
        )
    }

    private func __decode<T: Decodable>(
        _ type: T.Type,
        from payload: [String: Any]
    ) -> T? {
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(
                withJSONObject: payload
              )
        else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
