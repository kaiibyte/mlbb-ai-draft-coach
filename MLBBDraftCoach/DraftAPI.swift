
import Foundation

@MainActor
final class DraftAPI: ObservableObject {
    @Published var recommendation = ""
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let endpoint = URL(
        string: "https://mlbb-ai-draft-coach-5huhffn1q-kaiiiiiiii6767-5095.vercel.app/api/draft"
    )!

    func analyze(
        allied: [String],
        enemy: [String],
        lane: String = "Gold",
        rank: String = "glory"
    ) async {
        guard !isLoading else { return }

        isLoading = true
        errorMessage = nil

        defer { isLoading = false }

        do {
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.timeoutInterval = 60
            request.setValue(
                "application/json",
                forHTTPHeaderField: "Content-Type"
            )

            let body: [String: Any] = [
                "draft": [
                    "allied": allied,
                    "enemy": enemy,
                    "lane": lane,
                    "rank": rank,
                    "task": "Recommend the strongest available pick."
                ]
            ]

            request.httpBody = try JSONSerialization.data(
                withJSONObject: body
            )

            let (data, response) = try await URLSession.shared.data(
                for: request
            )

            guard let http = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }

            guard (200...299).contains(http.statusCode) else {
                let serverError =
                    (try? JSONSerialization.jsonObject(with: data))
                    as? [String: Any]

                throw NSError(
                    domain: "DraftAPI",
                    code: http.statusCode,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            serverError?["details"] as? String
                            ?? serverError?["error"] as? String
                            ?? "Draft analysis failed."
                    ]
                )
            }

            let result = try JSONSerialization.jsonObject(
                with: data
            ) as? [String: Any]

            let text = result?["recommendation"] as? String ?? ""

            guard !text.isEmpty else {
                throw NSError(
                    domain: "DraftAPI",
                    code: 1,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "The AI returned an empty recommendation."
                    ]
                )
            }

            recommendation = text

        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
