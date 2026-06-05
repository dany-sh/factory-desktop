import Foundation

public final class OllamaClient {
    private let endpoint: URL
    private let session: URLSession

    public init(endpoint: URL = URL(string: "http://localhost:11434/api/generate")!, session: URLSession = .shared) {
        self.endpoint = endpoint
        self.session = session
    }

    public func generate(model: String, prompt: String, contextTokens: Int) async throws -> String {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 600
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "prompt": prompt,
            "stream": false,
            "options": [
                "num_ctx": ModelPolicy.effectiveContext(for: model, requested: contextTokens)
            ]
        ])

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FactoryError.ollamaFailed("No HTTP response from Ollama.")
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw FactoryError.ollamaFailed("HTTP \(httpResponse.statusCode): \(body)")
        }

        let decoded = try JSONDecoder().decode(OllamaGenerateResponse.self, from: data)
        return decoded.response
    }
}

private struct OllamaGenerateResponse: Decodable {
    var response: String
}
