import Foundation

class TextEnhancer {
    private let endpoint = "https://api.anthropic.com/v1/messages"

    func enhance(transcript: String, apiKey: String) async throws -> String {
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 10

        let systemPrompt = "You are a dictation cleanup tool. The user will give you a raw speech transcript. Return ONLY the cleaned version of their exact words. Fix grammar and punctuation. Remove filler words (um, uh, like, you know). Do NOT add any new words, commentary, or change the meaning. If the transcript is already clean, return it as-is. Never explain what you're doing."

        let body: [String: Any] = [
            "model": "claude-haiku-4-5-20251001",
            "max_tokens": 1024,
            "system": systemPrompt,
            "messages": [
                ["role": "user", "content": transcript]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MurmurError.enhancementFailed("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw MurmurError.enhancementFailed("HTTP \(httpResponse.statusCode): \(errorBody)")
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let content = json?["content"] as? [[String: Any]],
              let firstBlock = content.first,
              let text = firstBlock["text"] as? String else {
            throw MurmurError.enhancementFailed("Could not parse response")
        }

        return text
    }
}
