import AVFoundation
@preconcurrency import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var nativeBridgeChannel: FlutterMethodChannel?
  private var audioEngine: AVAudioEngine?
  private var playerNode: AVAudioPlayerNode?
  private var streamSampleRate: Double = 24000

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions:
      [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    return super.application(
      application,
      didFinishLaunchingWithOptions: launchOptions
    )
  }

  override func applicationDidBecomeActive(
    _ application: UIApplication
  ) {
    super.applicationDidBecomeActive(application)
    setupNativeBridge()
  }

  private func setupNativeBridge() {
    guard nativeBridgeChannel == nil else { return }
    guard
      let controller =
        window?.rootViewController as? FlutterViewController
    else { return }

    let channel = FlutterMethodChannel(
      name: "native_bridge",
      binaryMessenger: controller.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "startStream":
        let sr =
          (call.arguments as? NSNumber)?.doubleValue
          ?? 24000
        self?.startStreaming(sampleRate: sr)
        result(nil)
      case "appendChunk":
        if let typed =
          call.arguments as? FlutterStandardTypedData
        {
          self?.appendChunk(typedData: typed)
        }
        result(nil)
      case "stopStream":
        self?.stopStreaming()
        result(nil)
      case "memory":
        result(Self.memoryFootprintMB())
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    nativeBridgeChannel = channel
  }

  private func startStreaming(sampleRate: Double) {
    stopStreaming()

    let engine = AVAudioEngine()
    let player = AVAudioPlayerNode()
    engine.attach(player)

    guard
      let format = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: sampleRate,
        channels: 1,
        interleaved: false
      )
    else { return }

    engine.connect(
      player, to: engine.mainMixerNode, format: format
    )

    do {
      try AVAudioSession.sharedInstance().setCategory(
        .playback, mode: .default
      )
      try AVAudioSession.sharedInstance().setActive(true)
      try engine.start()
    } catch {
      print("[AppDelegate] AVAudioEngine start failed: \(error)")
      return
    }

    player.play()
    audioEngine = engine
    playerNode = player
    streamSampleRate = sampleRate
  }

  private func appendChunk(
    typedData: FlutterStandardTypedData
  ) {
    guard let player = playerNode else { return }

    let doubles = typedData.data.withUnsafeBytes {
      Array($0.bindMemory(to: Double.self))
    }
    guard !doubles.isEmpty else { return }

    guard
      let format = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: streamSampleRate,
        channels: 1,
        interleaved: false
      )
    else { return }

    guard
      let buffer = AVAudioPCMBuffer(
        pcmFormat: format,
        frameCapacity: AVAudioFrameCount(doubles.count)
      )
    else { return }

    buffer.frameLength = AVAudioFrameCount(doubles.count)
    let channelData = buffer.floatChannelData![0]
    for i in 0..<doubles.count {
      channelData[i] = Float(doubles[i])
    }

    player.scheduleBuffer(buffer)
  }

  private func stopStreaming() {
    playerNode?.stop()
    audioEngine?.stop()
    playerNode = nil
    audioEngine = nil
  }

  private static func memoryFootprintMB() -> [String: Any] {
    var vmInfo = task_vm_info_data_t()
    var vmCount = mach_msg_type_number_t(
      MemoryLayout<task_vm_info_data_t>.size
        / MemoryLayout<integer_t>.size
    )
    let vmResult = withUnsafeMutablePointer(to: &vmInfo) {
      ptr in
      ptr.withMemoryRebound(
        to: integer_t.self, capacity: Int(vmCount)
      ) {
        task_info(
          mach_task_self_,
          task_flavor_t(TASK_VM_INFO),
          $0,
          &vmCount
        )
      }
    }

    let footprintMB: Double
    let residentMB: Double
    if vmResult == KERN_SUCCESS {
      footprintMB =
        Double(vmInfo.phys_footprint) / 1_048_576
      residentMB =
        Double(vmInfo.resident_size) / 1_048_576
    } else {
      footprintMB = -1
      residentMB = -1
    }

    return [
      "resident_mb": residentMB,
      "footprint_mb": footprintMB,
    ]
  }
}
