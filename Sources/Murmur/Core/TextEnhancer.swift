import Foundation

class TextEnhancer {
    private let endpoint = "https://api.anthropic.com/v1/messages"

    /// Enhanced dictation processing — context-aware like Wispr Flow
    func enhance(
        transcript: String,
        apiKey: String,
        contextBefore: String = "",
        selectedText: String = "",
        appName: String = "",
        appType: String = "document"
    ) async throws -> String {
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 10

        let isCommandMode = !selectedText.isEmpty

        let systemPrompt = buildSystemPrompt(
            appType: appType,
            appName: appName,
            isCommandMode: isCommandMode
        )

        let userMessage = buildUserMessage(
            transcript: transcript,
            contextBefore: contextBefore,
            selectedText: selectedText
        )

        let body: [String: Any] = [
            "model": "claude-haiku-4-5-20251001",
            "max_tokens": 2048,
            "system": systemPrompt,
            "messages": [
                ["role": "user", "content": userMessage]
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

    private func buildSystemPrompt(appType: String, appName: String, isCommandMode: Bool) -> String {
        if isCommandMode {
            return """
            You are a voice-controlled text editor. The user has selected text and spoken an editing instruction. \
            Apply the instruction to the selected text and return ONLY the modified result. \
            Do not add commentary, explanations, or quotes. \
            Examples of instructions: "make this more concise", "fix the grammar", "make this more formal", \
            "turn this into bullet points", "delete this", "rewrite this".
            If the instruction is "delete this" or "scratch that" or "remove this", return an empty string.
            """
        }

        let toneGuide: String
        switch appType {
        case "email":
            toneGuide = "The user is writing an email. Use clear, professional language with proper punctuation. Maintain a polished but natural tone."
        case "chat":
            toneGuide = "The user is in a messaging app. Keep it casual and conversational. Use shorter sentences. Skip overly formal punctuation. Lowercase is fine where natural."
        case "code":
            toneGuide = "The user is in a code editor. They are likely writing a comment, commit message, or documentation. Be precise and technical. Preserve any technical terms, variable names, or code references exactly as spoken."
        case "terminal":
            toneGuide = "The user is in a terminal. They may be writing a command, commit message, or note. Be concise and technical."
        default:
            toneGuide = "Match a natural writing tone appropriate for the context."
        }

        return """
        You are an intelligent voice dictation assistant that converts speech to polished text. \
        You must return ONLY the cleaned text — never add commentary, labels, or explanations.

        RULES:
        1. Fix grammar, punctuation, and capitalization naturally.
        2. Remove filler words (um, uh, like, you know, basically, actually, so, I mean) and false starts.
        3. If the user corrects themselves mid-sentence ("I want to... actually let's start with"), keep only the final intended version.
        4. Handle voice commands naturally:
           - "new line" or "new paragraph" → insert appropriate line break
           - "period", "comma", "question mark", "exclamation point" → insert the punctuation mark ONLY when clearly used as a voice command (not as a regular word in a sentence like "during this period")
           - "open quote"/"close quote" → quotation marks
           - "colon", "semicolon", "hyphen", "dash" → the punctuation character
        5. If there is preceding context, continue naturally from it — match the style, don't repeat what's already written, and ensure grammatical continuity.
        6. \(toneGuide)
        7. Do NOT add words, ideas, or content the user didn't say. Only clean up what they actually said.
        8. If the dictation is already clean, return it as-is.

        The user is dictating into: \(appName.isEmpty ? appType : "\(appName) (\(appType))")
        """
    }

    private func buildUserMessage(transcript: String, contextBefore: String, selectedText: String) -> String {
        if !selectedText.isEmpty {
            // Command mode: user selected text and spoke an instruction
            return """
            [SELECTED TEXT]
            \(selectedText)

            [VOICE INSTRUCTION]
            \(transcript)
            """
        }

        if !contextBefore.isEmpty {
            return """
            [EXISTING TEXT BEFORE CURSOR]
            \(contextBefore)

            [DICTATED SPEECH TO CLEAN UP]
            \(transcript)
            """
        }

        return transcript
    }
}
