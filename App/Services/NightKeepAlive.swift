import Foundation
import AVFoundation

/// Keeps Pulso running overnight without asking the strap for anything: a silent audio track (the app has the
/// audio background mode). An alarm needs the app awake to make the strap vibrate; before, the strap's live
/// stream did this from 10 h ahead, at the cost of a Bluetooth notification every second all night.
final class NightKeepAlive {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private var observers: [NSObjectProtocol] = []
    private(set) var running = false

    init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
    }

    func start() {
        guard !running, !AppMode.screenshots else { return }
        running = true
        let nc = NotificationCenter.default
        observers = [
            // A call or another app's audio stops the engine; pick up again when it ends.
            nc.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] n in
                let type = (n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init)
                if type == .ended { self?.play() }
            },
            nc.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
                self?.play()
            },
        ]
        play()
    }

    func stop() {
        guard running else { return }
        running = false
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        player.stop()
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// One second of silence on a loop, mixed with whatever else plays (music, podcasts, the voice coach).
    private func play() {
        guard running else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, options: [.mixWithOthers])
        try? session.setActive(true)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(format.sampleRate)),
              let data = buffer.floatChannelData else { return }
        buffer.frameLength = buffer.frameCapacity
        data[0].update(repeating: 0, count: Int(buffer.frameLength))
        player.stop()
        do { try engine.start() } catch { return }
        player.scheduleBuffer(buffer, at: nil, options: .loops)
        player.play()
    }
}
