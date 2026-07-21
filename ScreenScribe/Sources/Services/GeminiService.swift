import Foundation

/// Represents possible errors that can occur during Gemini API operations
enum GeminiAPIError: Error, LocalizedError {
    case apiKeyMissing
    case apiKeyInvalid
    case apiError(String)
    case requestFailed(Error)
    case invalidResponse
    case imageProcessingFailed
    case networkError(Error)
    case parsingError

    var errorDescription: String? {
        switch self {
        case .apiKeyMissing:
            return "Missing API key"
        case .apiKeyInvalid:
            return "Invalid API key"
        case .apiError(let message):
            return "API Error: \(message)"
        case .requestFailed(let error):
            return "Request failed: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from server"
        case .imageProcessingFailed:
            return "Failed to process image"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .parsingError:
            return "Failed to parse response"
        }
    }
}

/// Service responsible for handling AI-powered content extraction via Gemini API
@MainActor
struct GeminiService {
    private let session: URLSession
    private let maxRetries: Int
    private let initialDelay: UInt64
    
    init(session: URLSession = .shared, maxRetries: Int = 3, initialDelay: UInt64 = 1_000_000_000) {
        self.session = session
        self.maxRetries = maxRetries
        self.initialDelay = initialDelay
    }

    private func shouldRetry(statusCode: Int, error: Error?) -> Bool {
        // Implement retry logic here
        // For example:
        return statusCode >= 500 || error is URLError && (error as? URLError)?.code == .networkConnectionLost
    }

    static func makeRequest(
        base64Image: String,
        apiKey: String,
        promptContent: String,
        model: String
    ) throws -> URLRequest {
        let payload: [String: Any] = [
            "contents": [[
                "parts": [
                    ["inline_data": [
                        "mime_type": "image/png",
                        "data": base64Image
                    ]]
                ]
            ]],
            "systemInstruction": [
                "parts": [
                    ["text": promptContent]
                ]
            ],
            "generationConfig": [
                "maxOutputTokens": 2048
            ]
        ]

        guard let url = URL(string: "\(Config.geminiEndpoint(for: model))?key=\(apiKey)") else {
            throw GeminiAPIError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        return request
    }

    /// Extract content from an image using a customizable prompt
    /// - Parameters:
    ///   - base64Image: The image encoded as base64 PNG
    ///   - apiKey: The Gemini API key
    ///   - promptContent: The system prompt to use for extraction
    /// - Returns: The extracted content as a string
    func extractContent(from base64Image: String, apiKey: String, promptContent: String) async throws -> String {
        guard !apiKey.isEmpty else {
            throw GeminiAPIError.apiKeyMissing
        }

        // Get the selected model from UserDefaults
        let model = Config.requestGeminiModelID(
            from: UserDefaults.standard.string(forKey: "geminiModel")
        )
        let request = try Self.makeRequest(
            base64Image: base64Image,
            apiKey: apiKey,
            promptContent: promptContent,
            model: model
        )
        
        var retryCount = 0
        while retryCount <= maxRetries {
            do {
                let (data, response) = try await session.data(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw GeminiAPIError.invalidResponse
                }
                
                if httpResponse.statusCode != 200 {
                    if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let error = errorJson["error"] as? [String: Any],
                       let message = error["message"] as? String {
                        throw GeminiAPIError.apiError(message)
                    } else {
                        throw GeminiAPIError.apiError("API request failed with status \(httpResponse.statusCode)")
                    }
                }
                
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let candidates = json["candidates"] as? [[String: Any]],
                      let firstCandidate = candidates.first,
                      let content = firstCandidate["content"] as? [String: Any],
                      let parts = content["parts"] as? [[String: Any]],
                      let firstPart = parts.first,
                      let text = firstPart["text"] as? String else {
                    throw GeminiAPIError.parsingError
                }
                
                return text.trimmingCharacters(in: .whitespacesAndNewlines)
            } catch let error as GeminiAPIError {
                throw error
            } catch {
                if shouldRetry(statusCode: 0, error: error) {
                    retryCount += 1
                    try await Task.sleep(nanoseconds: initialDelay * UInt64(retryCount))
                } else {
                    throw GeminiAPIError.networkError(error)
                }
            }
        }
        
        throw GeminiAPIError.networkError(NSError(domain: "com.example.error", code: 0, userInfo: nil))
    }
}
