
import Foundation
import SwiftUI

@MainActor
final class DraftRecognitionManager: ObservableObject {

    @Published private(set) var detectedHeroes: [String] = []
    @Published private(set) var matchedText: [String] = []

    private var consecutiveMatches: [String: Int] = [:]

    func process(
        recognizedLines: [String],
        heroes: [MLBBHero]
    ) {
        matchedText = recognizedLines

        let availableHeroes = heroes.filter {
            normalize($0.name) != "wanwan"
        }

        var foundThisScan = Set<String>()

        for line in recognizedLines {
            let normalizedLine = normalize(line)

            guard !normalizedLine.isEmpty else { continue }

            for hero in availableHeroes {
                let normalizedName = normalize(hero.name)

                guard normalizedName.count >= 3 else { continue }

                if normalizedLine.contains(normalizedName) {
                    foundThisScan.insert(hero.name)
                }
            }
        }

        for hero in availableHeroes {
            if foundThisScan.contains(hero.name) {
                consecutiveMatches[hero.name, default: 0] += 1
            } else {
                consecutiveMatches[hero.name] = 0
            }
        }

        detectedHeroes = availableHeroes
            .filter {
                consecutiveMatches[$0.name, default: 0] >= 2
            }
            .map(\.name)
            .sorted()
    }

    func reset() {
        detectedHeroes = []
        matchedText = []
        consecutiveMatches.removeAll()
    }

    private func normalize(_ value: String) -> String {
        value
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }
}
