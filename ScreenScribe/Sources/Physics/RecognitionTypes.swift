import Foundation

enum RecognitionMode: String, Codable, CaseIterable, Identifiable {
    case equation, feynman
    var id: String { rawValue }
    var title: String { self == .equation ? "公式 → LaTeX" : "费曼图 → TikZ（实验性）" }
}

enum RecognitionBackend: String, Codable, CaseIterable, Identifiable {
    case mathpix, openAI
    var id: String { rawValue }
    var title: String { self == .mathpix ? "Mathpix" : "OpenAI 兼容视觉 API" }
}

struct RecognitionOutput: Codable, Equatable {
    var code: String
    var structure: String = ""
    var warnings: [String] = []
    var confidence: Double? = nil
}

struct RecognitionConfiguration {
    var backend: RecognitionBackend
    var model: String
    var baseURL: String
    var appID: String
    var apiKey: String
}

protocol RecognitionProvider {
    func recognize(png: Data, mode: RecognitionMode) async throws -> RecognitionOutput
}

enum RecognitionError: LocalizedError {
    case configuration(String), imageTooLarge, malformed, noMath, serviceRejected
    case mathpixOptionsConflict, mathpixNoContent, mathpixLowConfidence
    case http(Int), network, cancelled
    var errorDescription: String? {
        switch self {
        case .configuration(let message): return message
        case .imageTooLarge: return "截图超过此后端的上传限制，请缩小框选区域。未上传图片。"
        case .malformed: return "响应格式不符合要求或输出被截断。请检查服务的视觉支持，或重新识别。"
        case .noMath: return "未返回可验证的 LaTeX 数学字段。请只框选公式后重试。"
        case .mathpixOptionsConflict: return "Mathpix 请求选项冲突（opts_conflict）。请更新应用或检查请求配置。"
        case .mathpixNoContent: return "Mathpix 没有检测到可识别内容（image_no_content）。请先查看 Original 核对实际图片；若显示壁纸或错位，可使用系统截图后粘贴，或导入原图。"
        case .mathpixLowConfidence: return "Mathpix 对此图片的识别置信度不足（math_confidence）。请放大原文或重新框选。"
        case .serviceRejected: return "服务返回了识别错误。请检查图片、凭据及服务控制台。"
        case .http(401), .http(403): return "认证失败，请检查此服务的 API 凭据及访问权限。"
        case .http(429): return "请求被限流或余额不足（HTTP 429）。请查看服务控制台后重试。"
        case .http(let status): return "服务请求失败（HTTP \(status)）。请检查端点、模型和服务状态。"
        case .network: return "网络连接失败或请求超时。请检查网络后重试。"
        case .cancelled: return "已取消。"
        }
    }
}

enum LatexCopyFormat: String, CaseIterable, Identifiable {
    case plain = "纯公式", inline = "$…$", display = "\\[…\\]"
    var id: String { rawValue }
    func wrap(_ code: String) -> String {
        switch self {
        case .plain: return code
        case .inline: return "$\(code)$"
        case .display: return "\\[\n\(code)\n\\]"
        }
    }
}

enum EquationParser {
    // Only remove an enclosing wrapper; never replace internal newlines or alignment.
    static func unwrap(_ source: String) -> String {
        var value = source.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("```"), value.hasSuffix("```"), let line = value.firstIndex(of: "\n") {
            value = String(value[value.index(after: line)..<value.index(value.endIndex, offsetBy: -3)])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        for (open, close) in [("\\[", "\\]"), ("\\(", "\\)"), ("$$", "$$"), ("$", "$")] {
            if value.hasPrefix(open), value.hasSuffix(close), value.count >= open.count + close.count {
                return String(value.dropFirst(open.count).dropLast(close.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return value
    }
}

enum SnipCopyStyle: String, CaseIterable, Identifiable {
    case plain = "LaTeX", inline = "$ … $", display = "$$ … $$", equation = "equation"
    var id: String { rawValue }
    func source(_ code: String) -> String {
        switch self {
        case .plain: return code
        case .inline: return "$\(code)$"
        case .display: return "$$\n\(code)\n$$"
        case .equation: return "\\begin{equation}\n\(code)\n\\end{equation}"
        }
    }
}
