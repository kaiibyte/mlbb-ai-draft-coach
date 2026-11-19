
import Foundation
import SwiftUI

struct MLBBHero: Identifiable {
    let id: String
    let name: String
    let slug: String
    let role: String
    let lane: String
    let imageURL: String

    var image: URL? {
        URL(string: imageURL)
    }
}

@MainActor
final class HeroAPI: ObservableObject {
    @Published var heroes: [MLBBHero] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var lastUpdated: Date?

    private let baseURL = "https://mlbbdex.com/api/v1"

    func loadHeroes() async {
        guard !isLoading else { return }

        isLoading = true
        errorMessage = nil

        defer { isLoading = false }

        guard let url = URL(string: "\(baseURL)/heroes") else {
            errorMessage = "Invalid API address."
            return
        }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 20
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode) else {
                errorMessage = "Hero API returned an error."
                return
            }

            let json = try JSONSerialization.jsonObject(with: data)

            guard let root = json as? [String: Any],
                  let records = root["data"] as? [[String: Any]] else {
                errorMessage = "Unexpected hero API response."
                return
            }

            let fetchedHeroes = records.compactMap { item -> MLBBHero? in
                func value(_ keys: [String]) -> String {
                    for key in keys {
                        if let result = item[key] as? String {
                            return result
                        }
                        if let result = item[key] as? Int {
                            return String(result)
                        }
                    }
                    return ""
                }

                let name = value(["name", "title"])
                let slug = value(["slug", "id"])

                guard !name.isEmpty, !slug.isEmpty else {
                    return nil
                }

                return MLBBHero(
                    id: slug,
                    name: name,
                    slug: slug,
                    role: value(["role", "primary_role"]),
                    lane: value(["lane", "position"]),
                    imageURL: value(["image", "image_url", "portrait", "icon"])
                )
            }

            guard !fetchedHeroes.isEmpty else {
                errorMessage = "No heroes could be read from the API."
                return
            }

            heroes = fetchedHeroes.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }

            lastUpdated = Date()

        } catch {
            errorMessage = "Could not load heroes: \(error.localizedDescription)"
        }
    }

    func loadHeroDetails(slug: String) async throws -> Data {
        guard let encodedSlug = slug.addingPercentEncoding(
            withAllowedCharacters: .urlPathAllowed
        ),
        let url = URL(string: "\(baseURL)/heroes/\(encodedSlug)") else {
            throw URLError(.badURL)
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        return data
    }
}
