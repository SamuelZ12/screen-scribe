import Foundation

struct MathpixProvider: RecognitionProvider {
    let appID: String
    let apiKey: String
    var transport = APITransport()
    var beforeSend: (@Sendable () async -> Void)? = nil
    var afterSend: (@Sendable () async -> Void)? = nil

    func makeRequest(png: Data) throws -> URLRequest {
        guard !appID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !apiKey.isEmpty,
              !appID.contains(where: { $0.isNewline }), !apiKey.contains(where: { $0.isNewline }) else {
            throw RecognitionError.configuration("请在设置中保存 Mathpix App ID 和 App Key。")
        }
        let encoded = png.base64EncodedString()
        guard !png.isEmpty, encoded.utf8.count <= 2_000_000 else { throw RecognitionError.imageTooLarge }
        var request = URLRequest(url: URL(string: "https://api.mathpix.com/v3/text")!)
        request.httpMethod = "POST"
        request.setValue(appID, forHTTPHeaderField: "app_id")
        request.setValue(apiKey, forHTTPHeaderField: "app_key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "src": "data:image/png;base64,\(encoded)",
            "formats": ["latex_styled", "data"],
            "data_options": ["include_latex": true],
            "include_line_data": true,
            // Ask Mathpix to simplify equivalent source syntax without rewriting it locally.
            "rm_spaces": true, "idiomatic_braces": true, "idiomatic_eqn_arrays": false
        ])
        return request
    }

    func recognize(png: Data, mode: RecognitionMode) async throws -> RecognitionOutput {
        guard mode == .equation else {
            throw RecognitionError.configuration("Mathpix 未提供费曼图转 TikZ 接口。请选择视觉模型后端。")
        }
        let request = try makeRequest(png: png)
        try Task.checkCancellation()
        await beforeSend?()
        try Task.checkCancellation()
        do {
            let output = try Self.parse(await transport.send(request))
            await afterSend?()
            return output
        } catch {
            await afterSend?()
            throw error
        }
    }

    static func parse(_ data: Data) throws -> RecognitionOutput {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw RecognitionError.malformed }
        let errorText = (json["error"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let errorInfo = json["error_info"] as? [String: Any] ?? [:]
        if !errorText.isEmpty || !errorInfo.isEmpty {
            // Translate only known identifiers. Never surface a server message that might echo credentials.
            switch errorInfo["id"] as? String {
            case "opts_conflict": throw RecognitionError.mathpixOptionsConflict
            case "image_no_content": throw RecognitionError.mathpixNoContent
            case "math_confidence": throw RecognitionError.mathpixLowConfidence
            default: throw RecognitionError.serviceRejected
            }
        }
        if let error = json["error"], !(error is NSNull), !(error is String) { throw RecognitionError.serviceRejected }
        var warnings: [String] = []
        let code: String
        if let styled = json["latex_styled"] as? String, !styled.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            code = EquationParser.unwrap(styled)
        } else {
            let elements = (json["data"] as? [[String: Any]] ?? []).compactMap { element -> String? in
                guard element["type"] as? String == "latex", let value = element["value"] as? String,
                      !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
                return EquationParser.unwrap(value)
            }
            guard !elements.isEmpty else { throw RecognitionError.noMath }
            // Preserve each verified math fragment, without inferring alignment between separate equations.
            code = elements.count == 1 ? elements[0] : "\\begin{gathered}\n" + elements.joined(separator: " \\\\\n") + "\n\\end{gathered}"
            if elements.count > 1 { warnings.append("多个数学片段按返回顺序排列；原图的跨行对齐关系需人工核查。") }
        }
        if let confidence = json["confidence"] as? Double, confidence < 0.95 {
            warnings.append("整体置信度 \(Int(confidence * 100))%，请逐字符核对原图。")
        }
        for item in (json["word_data"] as? [[String: Any]] ?? []) {
            if let score = item["confidence"] as? Double, score < 0.95 {
                warnings.append("待确认字符或片段：\(item["latex"] as? String ?? item["text"] as? String ?? "位置未知")")
            }
        }
        for line in json["line_data"] as? [[String: Any]] ?? [] {
            if let confidence = line["confidence"] as? Double, confidence < 0.95 {
                warnings.append("待确认行（置信度 \(Int(confidence * 100))%）：\((line["text"] as? String ?? "未提供行文本").prefix(180))")
            }
            if line["conversion_output"] as? Bool == false {
                warnings.append("原图有未转换行（可能为编号、低置信内容或图形），请核对遗漏。")
            }
        }
        warnings.append("OCR 置信度无法定位全部歧义；未标记的符号也需核对。")
        guard !code.isEmpty else { throw RecognitionError.noMath }
        return RecognitionOutput(code: code, warnings: warnings, confidence: json["confidence"] as? Double)
    }
}
