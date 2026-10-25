import Foundation
import AVFoundation

/// Spoken cues for interval workouts (works with the screen locked thanks to the audio background mode).
final class VoiceCoach {
    private let synth = AVSpeechSynthesizer()
    private var sessionActive = false

    func say(_ text: String) {
        if !sessionActive {
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .voicePrompt,
                                                             options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
            try? AVAudioSession.sharedInstance().setActive(true)
            sessionActive = true
        }
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: "es-ES")
        u.rate = AVSpeechUtteranceDefaultSpeechRate * 1.05
        synth.speak(u)
    }

    func finish() {
        synth.stopSpeaking(at: .word)
        if sessionActive {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            sessionActive = false
        }
    }
}
