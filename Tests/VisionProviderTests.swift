import Foundation

@main struct VisionProviderTests {
    static func main() async throws {
        let configuration = RecognitionConfiguration(backend: .openAI, model: "user-vision-model", baseURL: "https://example.test/v1/", appID: "", apiKey: "fake-key")
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [MockProtocol.self]
        let provider = OpenAICompatibleVisionProvider(configuration: configuration, transport: APITransport(session: URLSession(configuration: config)))
        let request = try provider.makeRequest(png: Data([1,2]), mode: .feynman)
        expect(request.url?.absoluteString == "https://example.test/v1/chat/completions", "normalize endpoint")
        expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fake-key", "bearer auth")
        expect(request.url?.query == nil, "no secret in URL")
        let body = String(data: request.httpBody!, encoding: .utf8)!
        expect(body.contains("image_url") && body.contains("AQI="), "actual image content")
        expect(body.contains("uncertainties"), "independent diagram prompt")
        expect(!body.contains("app_key"), "never send Mathpix credentials")
        for invalid in ["http://example.test/v1", "https://user:password@example.test/v1", "https://example.test/v1?k=secret", "https://example.test/v1#x", "https://example.test/v1/chat/completions"] {
            do { _ = try OpenAICompatibleVisionProvider.endpoint(baseURL: invalid); fatalError("unsafe endpoint accepted") } catch {}
        }
        let firstAccount = try OpenAICompatibleVisionProvider.credentialAccount(baseURL: "https://one.test/v1")
        let secondAccount = try OpenAICompatibleVisionProvider.credentialAccount(baseURL: "https://two.test/v1")
        expect(firstAccount != secondAccount, "bind secrets to endpoint")
        func response(_ content: String, finish: String = "stop") throws -> Data {
            try JSONSerialization.data(withJSONObject: ["choices": [["finish_reason": finish, "message": ["content": content]]]])
        }
        MockProtocol.body = try response(#"\[\begin{aligned}a&=\frac{1}{2}\\b&=\Theta(x)\end{aligned}\]"#)
        let equation = try await provider.recognize(png: Data([1]), mode: .equation)
        expect(equation.code.hasPrefix("\\begin{aligned}"), "preserve multi-line source")
        let tikz = #"\documentclass{standalone}\usepackage{tikz-feynman}\begin{document}\begin{tikzpicture}\begin{feynman}\vertex (a) at (0,0);\vertex (b) at (2,0);\diagram*{(a)--[photon](b)};\end{feynman}\end{tikzpicture}\end{document}"#
        let diagramJSON = try JSONSerialization.data(withJSONObject: ["code":tikz,"structure":"a 与 b 由波浪线连接，粒子身份待确认。","uncertainties":["箭头方向不可读"]])
        MockProtocol.body = try response(String(data: diagramJSON, encoding: .utf8)!)
        let diagram = try await provider.recognize(png: Data([1]), mode: .feynman)
        expect(diagram.code == tikz && diagram.structure.contains("待确认"), "separate JSON parser")
        expect(diagram.warnings.contains { $0.contains("箭头") }, "uncertainty surfaced")
        for invalid in [try response("x", finish: "length"), try response("Here is your equation x=1"), try response("\\frac{a}{"), try response(""), json(#"{"choices":[{"finish_reason":"stop","message":{"refusal":"no","content":"x"}}]}"#)] {
            do { _ = try OpenAICompatibleVisionProvider.parse(invalid, mode: .equation); fatalError("bad output accepted") } catch {}
        }
        do { _ = try FeynmanParser.parse("x=y"); fatalError("equation parser used for diagram") } catch {}
        let malicious = tikz.replacingOccurrences(of: "\\end{document}", with: "\\input{private}\\end{document}")
        let bad = try JSONSerialization.data(withJSONObject: ["code":malicious,"structure":"x","uncertainties":[]])
        do { _ = try FeynmanParser.parse(String(data: bad, encoding: .utf8)!); fatalError("file access accepted") } catch {}
        expect(!LatexValidation.balanced(#"\begin{aligned}x\end{matrix}"#), "environment matching")
        expect(LatexValidation.balanced(#"\left\{x\right\}"#), "escaped braces")
        MockProtocol.status = 429
        do { _ = try await provider.recognize(png: Data([1]), mode: .equation); fatalError("rate limit accepted") } catch {}
        print("VisionProviderTests passed: vision payload, endpoint validation/binding, independent parsers, truncation/refusal, uncertainty, rate limits")
    }
}
