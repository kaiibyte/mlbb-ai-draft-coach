
import Foundation
import AVFoundation

@MainActor
final class VoiceCoach: ObservableObject {

    @Published private(set) var isSpeaking = false

    private let synthesizer = AVSpeechSynthesizer()
    private var lastAnnouncement = ""
    private var lastMessage = ""

    func announce(
        bestPick: String,
        alternatives: [String],
        isYourTurn: Bool
    ) {
        guard isYourTurn else { return }
        guard !bestPick.isEmpty else { return }

        let filteredAlternatives = Array(
            alternatives
                .filter {
                    !$0.isEmpty &&
                    $0.lowercased() != bestPick.lowercased()
                }
                .prefix(5)
        )

        let message: String

        if filteredAlternatives.isEmpty {
            message = "Pick \(bestPick)."
        } else {
            message = """
            Pick \(bestPick). Alternatives: \
            \(filteredAlternatives.joined(separator: ", ")).
            """
        }

        guard message != lastAnnouncement else { return }

        lastAnnouncement = message
        lastMessage = message

        synthesizer.stopSpeaking(at: .immediate)

        let utterance = AVSpeechUtterance(string: message)
        utterance.rate = 0.48
        utterance.volume = 1.0

        isSpeaking = true
        synthesizer.speak(utterance)
    }

    func replay() {
        guard !lastMessage.isEmpty else { return }

        synthesizer.stopSpeaking(at: .immediate)

        let utterance = AVSpeechUtterance(string: lastMessage)
        utterance.rate = 0.48
        utterance.volume = 1.0

        isSpeaking = true
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
    }

    func resetAnnouncement() {
        lastAnnouncement = ""
    }
}
