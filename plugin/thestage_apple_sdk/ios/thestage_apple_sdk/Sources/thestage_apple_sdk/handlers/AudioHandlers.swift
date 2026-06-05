@preconcurrency import Flutter
import Foundation
import TheStageCore

// --------------------------------------------------------------------------------------
// Audio Handlers
// --------------------------------------------------------------------------------------
extension TheStageFlutterPlugin {

    func __handle_audio_start(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        guard let args = call.arguments as? [String: Any],
              let player_id = args["player_id"] as? String
        else {
            __fail(result, msg: "Missing player_id.")
            return
        }
        if let existing = __audio_players[player_id] {
            existing.stop()
            __audio_players.removeValue(forKey: player_id)
        }
        let sr = (args["sample_rate"] as? NSNumber)?
            .doubleValue ?? 24000
        let player = TheStageCore.AudioStreamPlayer(
            sample_rate: sr
        )
        player.start()
        __audio_players[player_id] = player
        result(nil)
    }

    func __handle_audio_enqueue(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        guard let args = call.arguments as? [String: Any],
              let player_id = args["player_id"] as? String
        else {
            result(nil)
            return
        }
        if let typed = args["audio"] as? FlutterStandardTypedData {
            let count = typed.data.count / MemoryLayout<Float>.size
            let samples: [Float] = typed.data.withUnsafeBytes { raw in
                let floats = raw.bindMemory(to: Float.self)
                return Array(floats.prefix(count))
            }
            __audio_players[player_id]?.enqueue(samples)
        }
        result(nil)
    }

    func __handle_audio_pause(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        guard let args = call.arguments as? [String: Any],
              let player_id = args["player_id"] as? String
        else {
            result(nil)
            return
        }
        __audio_players[player_id]?.pause()
        result(nil)
    }

    func __handle_audio_resume(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        guard let args = call.arguments as? [String: Any],
              let player_id = args["player_id"] as? String
        else {
            result(nil)
            return
        }
        __audio_players[player_id]?.resume()
        result(nil)
    }

    func __handle_audio_drain(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        guard let args = call.arguments as? [String: Any],
              let player_id = args["player_id"] as? String
        else {
            result(nil)
            return
        }
        guard let player = __audio_players[player_id] else {
            result(nil)
            return
        }
        player.drain { result(nil) }
    }

    func __handle_audio_stop(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        guard let args = call.arguments as? [String: Any],
              let player_id = args["player_id"] as? String
        else {
            result(nil)
            return
        }
        __audio_players[player_id]?.stop()
        __audio_players.removeValue(forKey: player_id)
        result(nil)
    }
}
