import AVFoundation

/// Gapless streaming PCM playback (same pattern as EngineBench / Mac demo).
final class StreamPlayer {
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let format: AVAudioFormat
    private let lock = NSLock()
    private var pending = 0
    private var drainWaiters: [CheckedContinuation<Void, Never>] = []

    init(rate: Double = 24_000) {
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
        format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: rate,
            channels: 1, interleaved: false
        )!
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        try? engine.start()
        node.play()
    }

    func enqueue(_ pcm: [Float]) {
        guard !pcm.isEmpty else { return }
        guard let buf = AVAudioPCMBuffer(
            pcmFormat: format, frameCapacity: AVAudioFrameCount(pcm.count)
        ) else { return }
        buf.frameLength = AVAudioFrameCount(pcm.count)
        pcm.withUnsafeBufferPointer { src in
            buf.floatChannelData![0].update(
                from: src.baseAddress!, count: pcm.count
            )
        }
        lock.lock()
        pending += 1
        lock.unlock()
        node.scheduleBuffer(buf) { [weak self] in
            self?.bufferFinished()
        }
    }

    /// Wait until every scheduled buffer has finished playing.
    func waitUntilDrained() async {
        lock.lock()
        if pending == 0 {
            lock.unlock()
            return
        }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            drainWaiters.append(cont)
            lock.unlock()
        }
    }

    func stop() {
        lock.lock()
        pending = 0
        let waiters = drainWaiters
        drainWaiters.removeAll()
        lock.unlock()
        node.stop()
        engine.stop()
        for w in waiters { w.resume() }
    }

    private func bufferFinished() {
        lock.lock()
        pending = max(0, pending - 1)
        let done = pending == 0
        let waiters = done ? drainWaiters : []
        if done { drainWaiters.removeAll() }
        lock.unlock()
        if done {
            for w in waiters { w.resume() }
        }
    }
}
