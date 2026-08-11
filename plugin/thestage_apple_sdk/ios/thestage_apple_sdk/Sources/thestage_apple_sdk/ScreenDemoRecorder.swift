import AVFoundation
import CoreMedia
import Photos
import ReplayKit
import TheStageCore
import UIKit

/// In-app screen capture for Flutter hosts. Keeps live AEC / voiceChat on.
/// Video: ReplayKit. Audio: stereo Linear PCM — L = mic, R = TTS.
///
/// Recording levels/mix do **not** affect what models hear — `DemoAudioCapture`
/// is a tee after the live path. Mic gain here is record-only.
final class ScreenDemoRecorder {
    static let shared = ScreenDemoRecorder()

    private let queue = DispatchQueue(label: "ai.thestage.screen_demo_recorder")
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var outputURL: URL?
    private var sessionStarted = false
    private var isCapturing = false
    private var flushTimer: DispatchSourceTimer?

    private let mixSampleRate: Double = 24_000
    /// ~20 ms chunks keep A/V aligned without dumping huge mic backlogs.
    private let chunkFrames = 480
    /// Leave this much wall-clock latency so late TTS can still land.
    private let latencyFrames = 1_440 // 60 ms
    private var audioFramesWritten: Int64 = 0
    private var recordingStartHost: CFTimeInterval = 0
    private var recordingStartPTS: CMTime = .invalid

    /// TTS only (mono), indexed by output frame. Mic uses ``micFifo``.
    private var ttsTimeline = [Float]()
    private var ttsTimelineStartFrame: Int64 = 0
    private var ttsWriteFrame: Int64 = -1
    private let timelineLock = NSLock()

    /// Continuous mic samples at ``mixSampleRate``. Drained on flush by
    /// wall-clock — avoids silence holes from late wall-frame placement.
    private var micFifo = [Float]()
    /// Cap ~250 ms so a stalled flush cannot grow forever.
    private let micFifoMax = 6_000
    /// Fixed record-only attenuator (no per-chunk normalize → no pumping).
    private let micGain: Float = 0.45
    private let ttsGain: Float = 0.9

    var recording: Bool { isCapturing }

    func start() async throws {
        if isCapturing { return }

        let recorder = RPScreenRecorder.shared()
        guard recorder.isAvailable else {
            throw RecorderError.unavailable
        }

        let photos = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard photos == .authorized || photos == .limited else {
            throw RecorderError.photosDenied
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("va_demo_\(Int(Date().timeIntervalSince1970)).mov")
        try? FileManager.default.removeItem(at: url)

        let assetWriter = try AVAssetWriter(outputURL: url, fileType: .mov)

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            DispatchQueue.main.async {
                self.outputURL = url
                self.writer = assetWriter
                self.sessionStarted = false
                self.audioFramesWritten = 0
                self.recordingStartHost = 0
                self.recordingStartPTS = .invalid
                self.ttsWriteFrame = -1
                self.videoInput = nil
                self.audioInput = nil
                self.timelineLock.lock()
                self.ttsTimeline.removeAll(keepingCapacity: true)
                self.ttsTimelineStartFrame = 0
                self.micFifo.removeAll(keepingCapacity: true)
                self.timelineLock.unlock()

                recorder.isMicrophoneEnabled = false

                // Copy on the producer thread, then hop — never do I/O here.
                TheStageCore.DemoAudioCapture.enabled = true
                TheStageCore.DemoAudioCapture.on_playback = { [weak self] samples, sr in
                    let copy = samples
                    self?.queue.async {
                        self?.placeTTS(samples: copy, sampleRate: sr)
                    }
                }
                TheStageCore.DemoAudioCapture.on_mic = { [weak self] samples, sr in
                    let copy = samples
                    self?.queue.async {
                        self?.enqueueMic(samples: copy, sampleRate: sr)
                    }
                }

                recorder.startCapture(handler: { [weak self] sample, type, error in
                    guard let self else { return }
                    if let error {
                        NSLog("ScreenDemoRecorder buffer error: \(error)")
                        return
                    }
                    guard type == .video else { return }
                    self.queue.async { self.appendVideo(sample) }
                }, completionHandler: { [weak self] error in
                    guard let self else {
                        cont.resume(throwing: RecorderError.unavailable)
                        return
                    }
                    if let error {
                        NSLog("ScreenDemoRecorder start failed: \(error)")
                        self.teardownCapture(keepFile: false)
                        cont.resume(throwing: error)
                        return
                    }
                    self.isCapturing = true
                    cont.resume()
                })
            }
        }
    }

    func stop() async throws {
        guard isCapturing else { throw RecorderError.notRecording }
        isCapturing = false
        TheStageCore.DemoAudioCapture.enabled = false
        TheStageCore.DemoAudioCapture.on_playback = nil
        TheStageCore.DemoAudioCapture.on_mic = nil
        stopFlushTimer()

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            DispatchQueue.main.async {
                RPScreenRecorder.shared().stopCapture { [weak self] error in
                    guard let self else {
                        cont.resume(throwing: RecorderError.notRecording)
                        return
                    }
                    if let error {
                        self.teardownCapture(keepFile: false)
                        cont.resume(throwing: error)
                        return
                    }
                    self.queue.async {
                        self.flushAudio(force: true)
                        self.finishAndSave { result in
                            switch result {
                            case .success: cont.resume()
                            case .failure(let e): cont.resume(throwing: e)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Mic FIFO + TTS wall timeline

    private func enqueueMic(samples: [Float], sampleRate: Double) {
        guard sessionStarted, recordingStartHost > 0 else { return }
        let resampled = resample(samples, from: sampleRate, to: mixSampleRate)
        guard !resampled.isEmpty else { return }

        timelineLock.lock()
        for s in resampled {
            micFifo.append(max(-1, min(1, s * micGain)))
        }
        if micFifo.count > micFifoMax {
            micFifo.removeFirst(micFifo.count - micFifoMax)
        }
        timelineLock.unlock()
        flushAudio(force: false)
    }

    private func placeTTS(samples: [Float], sampleRate: Double) {
        guard sessionStarted, recordingStartHost > 0 else { return }
        let resampled = resample(samples, from: sampleRate, to: mixSampleRate)
        guard !resampled.isEmpty else { return }

        let leveled = resampled.map { min(1, max(-1, $0 * ttsGain)) }
        let hostNow = CACurrentMediaTime()
        let wallFrame = Int64((hostNow - recordingStartHost) * mixSampleRate)
        let count = Int64(leveled.count)

        let startFrame: Int64
        if ttsWriteFrame < 0 || wallFrame >= ttsWriteFrame {
            startFrame = wallFrame
        } else {
            startFrame = ttsWriteFrame
        }
        ttsWriteFrame = startFrame + count

        timelineLock.lock()
        ensureTTSCapacity(through: startFrame + count)
        for i in 0..<leveled.count {
            let frame = startFrame + Int64(i)
            let idx = Int(frame - ttsTimelineStartFrame)
            guard idx >= 0, idx < ttsTimeline.count else { continue }
            ttsTimeline[idx] = leveled[i]
        }
        timelineLock.unlock()
        flushAudio(force: false)
    }

    private func ensureTTSCapacity(through frame: Int64) {
        if ttsTimeline.isEmpty {
            ttsTimelineStartFrame = max(0, frame - Int64(chunkFrames))
        }
        let needFrames = Int(frame - ttsTimelineStartFrame) + chunkFrames
        if ttsTimeline.count < needFrames {
            ttsTimeline.append(
                contentsOf: repeatElement(0, count: needFrames - ttsTimeline.count)
            )
        }
        let dropBefore = audioFramesWritten - Int64(latencyFrames)
        if dropBefore > ttsTimelineStartFrame + Int64(chunkFrames * 4) {
            let dropFrames = Int(dropBefore - ttsTimelineStartFrame)
            if dropFrames > 0, dropFrames < ttsTimeline.count {
                ttsTimeline.removeFirst(dropFrames)
                ttsTimelineStartFrame = dropBefore
            }
        }
    }

    private func startFlushTimer() {
        stopFlushTimer()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(20))
        timer.setEventHandler { [weak self] in
            self?.flushAudio(force: false)
        }
        timer.resume()
        flushTimer = timer
    }

    private func stopFlushTimer() {
        flushTimer?.cancel()
        flushTimer = nil
    }

    private func flushAudio(force: Bool) {
        guard sessionStarted, let writer, writer.status == .writing,
              let audioInput, audioInput.isReadyForMoreMediaData
        else { return }
        guard recordingStartHost > 0 else { return }

        let hostNow = CACurrentMediaTime()
        let liveFrame = Int64((hostNow - recordingStartHost) * mixSampleRate)
        let target = force ? liveFrame : (liveFrame - Int64(latencyFrames))
        guard target > audioFramesWritten else { return }

        while audioFramesWritten < target {
            guard audioInput.isReadyForMoreMediaData else { return }
            let frames = min(chunkFrames, Int(target - audioFramesWritten))
            guard frames > 0 else { return }

            var interleaved = [Float](repeating: 0, count: frames * 2)
            timelineLock.lock()
            for i in 0..<frames {
                let frame = audioFramesWritten + Int64(i)
                // L = mic FIFO (continuous). Empty → brief 0, not a hole pattern.
                let mic: Float
                if !micFifo.isEmpty {
                    mic = micFifo.removeFirst()
                } else {
                    mic = 0
                }
                interleaved[i * 2] = mic

                let ttsIdx = Int(frame - ttsTimelineStartFrame)
                if ttsIdx >= 0, ttsIdx < ttsTimeline.count {
                    interleaved[i * 2 + 1] = ttsTimeline[ttsIdx]
                    ttsTimeline[ttsIdx] = 0
                }
            }
            timelineLock.unlock()

            guard let buffer = makeInt16StereoBuffer(
                interleaved: interleaved, frameCount: frames
            ) else { return }
            if !audioInput.append(buffer) {
                NSLog(
                    "ScreenDemoRecorder audio append failed: \(String(describing: writer.error))"
                )
                return
            }
            audioFramesWritten += Int64(frames)
        }
    }

    private func makeInt16StereoBuffer(
        interleaved: [Float], frameCount: Int
    ) -> CMSampleBuffer? {
        guard frameCount > 0, interleaved.count >= frameCount * 2 else { return nil }

        var int16 = [Int16](repeating: 0, count: frameCount * 2)
        for i in 0..<(frameCount * 2) {
            let clipped = max(-1, min(1, interleaved[i]))
            int16[i] = Int16((clipped * Float(Int16.max)).rounded())
        }

        var asbd = AudioStreamBasicDescription(
            mSampleRate: mixSampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kLinearPCMFormatFlagIsSignedInteger
                | kLinearPCMFormatFlagIsPacked,
            mBytesPerPacket: 4,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4,
            mChannelsPerFrame: 2,
            mBitsPerChannel: 16,
            mReserved: 0
        )

        var format: CMAudioFormatDescription?
        guard CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &asbd,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &format
        ) == noErr, let format else { return nil }

        let dataSize = frameCount * 2 * MemoryLayout<Int16>.size
        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: dataSize,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: dataSize,
            flags: 0,
            blockBufferOut: &block
        ) == noErr, let block else { return nil }

        int16.withUnsafeBytes { raw in
            _ = CMBlockBufferReplaceDataBytes(
                with: raw.baseAddress!,
                blockBuffer: block,
                offsetIntoDestination: 0,
                dataLength: dataSize
            )
        }

        var timing = CMSampleTimingInfo(
            duration: CMTimeMake(value: Int64(frameCount), timescale: Int32(mixSampleRate)),
            presentationTimeStamp: CMTimeAdd(
                recordingStartPTS,
                CMTimeMake(value: audioFramesWritten, timescale: Int32(mixSampleRate))
            ),
            decodeTimeStamp: .invalid
        )
        var sampleBuffer: CMSampleBuffer?
        var sampleSize = 4
        guard CMSampleBufferCreate(
            allocator: kCFAllocatorDefault,
            dataBuffer: block,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: format,
            sampleCount: frameCount,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSize,
            sampleBufferOut: &sampleBuffer
        ) == noErr else { return nil }
        return sampleBuffer
    }

    private func resample(
        _ samples: [Float], from: Double, to: Double
    ) -> [Float] {
        if from <= 0 || to <= 0 { return samples }
        if abs(from - to) < 0.5 { return samples }
        let ratio = to / from
        let outCount = max(1, Int((Double(samples.count) * ratio).rounded()))
        var out = [Float](repeating: 0, count: outCount)
        for i in 0..<outCount {
            let src = Double(i) / ratio
            let i0 = Int(src)
            let i1 = min(i0 + 1, samples.count - 1)
            let frac = Float(src - Double(i0))
            out[i] = samples[i0] * (1 - frac) + samples[i1] * frac
        }
        return out
    }

    // MARK: - Video

    private func appendVideo(_ sample: CMSampleBuffer) {
        guard CMSampleBufferDataIsReady(sample), let writer else { return }
        prepareInputsIfNeeded(sample: sample)
        guard let videoInput else { return }

        let pts = CMSampleBufferGetPresentationTimeStamp(sample)
        if writer.status == .unknown {
            writer.startWriting()
            writer.startSession(atSourceTime: pts)
            sessionStarted = true
            recordingStartPTS = pts
            recordingStartHost = CACurrentMediaTime()
            audioFramesWritten = 0
            startFlushTimer()
        }

        guard sessionStarted, writer.status == .writing,
              videoInput.isReadyForMoreMediaData
        else { return }

        if !videoInput.append(sample) {
            NSLog(
                "ScreenDemoRecorder video append failed: \(String(describing: writer.error))"
            )
        }
        flushAudio(force: false)
    }

    private func prepareInputsIfNeeded(sample: CMSampleBuffer) {
        guard videoInput == nil, let writer else { return }
        guard let format = CMSampleBufferGetFormatDescription(sample) else { return }
        let dims = CMVideoFormatDescriptionGetDimensions(format)
        let width = Int(dims.width)
        let height = Int(dims.height)
        guard width > 0, height > 0 else { return }

        let video = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.hevc,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
            ]
        )
        video.expectsMediaDataInRealTime = true
        guard writer.canAdd(video) else { return }
        writer.add(video)
        videoInput = video

        let audio = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: mixSampleRate,
                AVNumberOfChannelsKey: 2,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false,
            ]
        )
        audio.expectsMediaDataInRealTime = true
        if writer.canAdd(audio) {
            writer.add(audio)
            audioInput = audio
        }
    }

    private func finishAndSave(completion: @escaping (Result<Void, Error>) -> Void) {
        guard let writer, let url = outputURL else {
            completion(.failure(RecorderError.notRecording))
            return
        }
        if !sessionStarted || writer.status == .unknown {
            writer.cancelWriting()
            teardownCapture(keepFile: false)
            completion(.failure(RecorderError.noFrames))
            return
        }
        if writer.status == .failed {
            let err = writer.error ?? RecorderError.writeFailed
            teardownCapture(keepFile: false)
            completion(.failure(err))
            return
        }

        videoInput?.markAsFinished()
        audioInput?.markAsFinished()

        writer.finishWriting {
            let status = writer.status
            let error = writer.error
            let out = url
            self.resetWriter()
            if status != .completed {
                completion(.failure(error ?? RecorderError.writeFailed))
                return
            }
            self.saveToPhotos(url: out, completion: completion)
        }
    }

    private func saveToPhotos(url: URL, completion: @escaping (Result<Void, Error>) -> Void) {
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        }) { ok, error in
            try? FileManager.default.removeItem(at: url)
            if let error {
                completion(.failure(error))
            } else if !ok {
                completion(.failure(RecorderError.writeFailed))
            } else {
                completion(.success(()))
            }
        }
    }

    private func teardownCapture(keepFile: Bool) {
        isCapturing = false
        stopFlushTimer()
        TheStageCore.DemoAudioCapture.enabled = false
        TheStageCore.DemoAudioCapture.on_playback = nil
        TheStageCore.DemoAudioCapture.on_mic = nil
        if !keepFile, let url = outputURL {
            try? FileManager.default.removeItem(at: url)
        }
        resetWriter()
    }

    private func resetWriter() {
        writer = nil
        videoInput = nil
        audioInput = nil
        outputURL = nil
        sessionStarted = false
        audioFramesWritten = 0
        recordingStartHost = 0
        recordingStartPTS = .invalid
        ttsWriteFrame = -1
        timelineLock.lock()
        ttsTimeline.removeAll()
        ttsTimelineStartFrame = 0
        micFifo.removeAll()
        timelineLock.unlock()
    }

    enum RecorderError: LocalizedError {
        case unavailable
        case notRecording
        case writeFailed
        case photosDenied
        case noFrames

        var errorDescription: String? {
            switch self {
            case .unavailable:
                return "Screen recording unavailable (another recording may be active)."
            case .notRecording:
                return "No active screen recording."
            case .writeFailed:
                return "Failed to write the recording."
            case .photosDenied:
                return "Photos access denied — allow adding videos in Settings."
            case .noFrames:
                return "Recording produced no video frames."
            }
        }
    }
}
