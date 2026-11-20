
import Foundation

struct ParsedRecommendation {
    let bestPick: String
    let alternatives: [String]
}

enum RecommendationParser {

    static func parse(
        _ text: String,
        availableHeroes: [MLBBHero]
    ) -> ParsedRecommendation? {

        let heroes = availableHeroes
            .filter { $0.name.lowercased() != "wanwan" }

        let lines = text.components(separatedBy: .newlines)

        func extractHero(from text: String) -> String? {
            let cleaned = text
                .replacingOccurrences(
                    of: #"^\s*[-*•\d.)]+\s*"#,
                    with: "",
                    options: .regularExpression
                )
                .trimmingCharacters(in: .whitespacesAndNewlines)

            return heroes.first {
                cleaned.localizedCaseInsensitiveContains($0.name)
            }?.name
        }

        var bestPick: String?
        var alternatives: [String] = []
        var readingAlternatives = false

        for line in lines {
            let trimmed = line.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

            let upper = trimmed.uppercased()

            if upper.hasPrefix("BEST PICK:") {
                let value = String(
                    trimmed.dropFirst("BEST PICK:".count)
                )
                bestPick = extractHero(from: value)
                readingAlternatives = false
                continue
            }

            if upper.hasPrefix("ALTERNATIVES:") {
                readingAlternatives = true

                let value = String(
                    trimmed.dropFirst("ALTERNATIVES:".count)
                )

                if let hero = extractHero(from: value) {
                    alternatives.append(hero)
                }

                continue
            }

            if upper.hasPrefix("REASON:")
                || upper.hasPrefix("LANE:")
                || upper.hasPrefix("WARNINGS:") {
                readingAlternatives = false
                continue
            }

            if readingAlternatives,
               let hero = extractHero(from: trimmed),
               !alternatives.contains(hero) {
                alternatives.append(hero)
            }
        }

        guard let bestPick else {
            return nil
        }

        alternatives = alternatives
            .filter { $0 != bestPick }
            .prefix(5)
            .map { $0 }

        return ParsedRecommendation(
            bestPick: bestPick,
            alternatives: alternatives
        )
    }
}
