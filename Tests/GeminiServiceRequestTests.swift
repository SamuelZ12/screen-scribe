import Foundation

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

@main
struct GeminiServiceRequestTests {
    @MainActor
    static func main() {
        do {
            let request = try GeminiService.makeRequest(
                base64Image: "encoded-image",
                apiKey: "test-api-key",
                promptContent: "Return LaTeX",
                model: "gemini-3.6-flash"
            )

            expect(request.url?.path.contains("/models/gemini-3.6-flash:generateContent") == true,
                   "Requests should use the selected Gemini 3.6 Flash model")
            expect(request.httpMethod == "POST", "Requests should use POST")

            guard let body = request.httpBody,
                  let payload = try JSONSerialization.jsonObject(with: body) as? [String: Any],
                  let generationConfig = payload["generationConfig"] as? [String: Any] else {
                fputs("FAIL: Request should contain a JSON generation config\n", stderr)
                exit(1)
            }

            expect(generationConfig["temperature"] == nil,
                   "Requests should omit the deprecated temperature parameter")
            expect(generationConfig["candidateCount"] == nil,
                   "Requests should omit the unsupported candidateCount parameter")
            expect(generationConfig["maxOutputTokens"] as? Int == 2048,
                   "Requests should retain the output token limit")

            print("GeminiServiceRequestTests passed")
        } catch {
            fputs("FAIL: \(error)\n", stderr)
            exit(1)
        }
    }
}
