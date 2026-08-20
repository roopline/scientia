import AVFoundation
import Foundation
import UIKit

/// 判定結果の音声読み上げとバイブレーション。
/// 手元がふさがる作業なので、画面を見なくても OK / NG が分かるようにする。
final class Announcer {

    private let synthesizer = AVSpeechSynthesizer()

    init() {
        configureAudioSession()
    }

    private func configureAudioSession() {
        do {
            // 他アプリの音を止めずに読み上げる
            try AVAudioSession.sharedInstance().setCategory(.playback,
                                                            mode: .spokenAudio,
                                                            options: [.duckOthers, .mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true, options: [])
        } catch {
            // 音が出せなくてもハプティクスと画面表示で運用できる
        }
    }

    func announce(_ result: CheckResult, settings: AnnouncementSettings) {
        if settings.hapticsEnabled {
            let generator = UINotificationFeedbackGenerator()
            switch result.verdict {
            case .ok: generator.notificationOccurred(.success)
            case .warning, .noBarcode: generator.notificationOccurred(.warning)
            case .ng, .unknownProduct: generator.notificationOccurred(.error)
            }
        }

        guard settings.speechEnabled else { return }
        if result.verdict == .ok && !settings.speakOnSuccess { return }
        speak(result.spokenText)
    }

    func speak(_ text: String) {
        guard !text.isEmpty else { return }
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "ja-JP")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.05
        utterance.postUtteranceDelay = 0.1
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    struct AnnouncementSettings {
        var speechEnabled: Bool
        var speakOnSuccess: Bool
        var hapticsEnabled: Bool
    }
}
