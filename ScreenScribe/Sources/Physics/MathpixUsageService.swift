import Foundation

struct MathpixUsageSnapshot: Equatable {
    let appID: String
    let imageCount: Int
    let periodStart: Date
    let periodEnd: Date
    let fetchedAt: Date
}

enum MathpixUsageError: LocalizedError {
    case configuration, malformed, serviceRejected, incomplete

    var errorDescription: String? {
        switch self {
        case .configuration: return "请先保存有效的 Mathpix App ID 和 App Key，再查询用量。"
        case .malformed: return "Mathpix 用量响应格式不符合要求，请稍后刷新。"
        case .serviceRejected: return "Mathpix 暂未返回可用的用量数据，请查看服务控制台。"
        case .incomplete: return "Mathpix 用量数据可能不完整，请查看控制台。"
        }
    }
}

struct MathpixUsageService {
    private static let pageSize = 100
    let appID: String
    let apiKey: String
    var transport = APITransport()

    func makeRequest(now: Date = Date()) throws -> URLRequest {
        guard !appID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !appID.contains(where: { $0.isNewline }),
              !apiKey.contains(where: { $0.isNewline }) else {
            throw MathpixUsageError.configuration
        }
        let period = try Self.month(containing: now)
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var components = URLComponents(string: "https://api.mathpix.com/v3/ocr-usage")!
        components.queryItems = [
            URLQueryItem(name: "from_date", value: formatter.string(from: period.start)),
            URLQueryItem(name: "to_date", value: formatter.string(from: period.end)),
            // The official SDK sends list-valued group_by as repeated query items.
            // Keep App ID in the grouping so each row can be scoped before summing.
            URLQueryItem(name: "group_by", value: "app_id"),
            URLQueryItem(name: "group_by", value: "usage_type"),
            URLQueryItem(name: "timespan", value: "month"),
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "per_page", value: String(Self.pageSize))
        ]
        guard let url = components.url else { throw MathpixUsageError.configuration }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue(appID, forHTTPHeaderField: "app_id")
        request.setValue(apiKey, forHTTPHeaderField: "app_key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    func fetch(now: Date = Date()) async throws -> MathpixUsageSnapshot {
        let data = try await transport.send(makeRequest(now: now))
        return try Self.parse(data, appID: appID, now: now)
    }

    static func parse(_ data: Data, appID: String, now: Date = Date()) throws -> MathpixUsageSnapshot {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MathpixUsageError.malformed
        }
        // Service text can echo request data. Return only our own fixed messages.
        if let error = json["error"], !(error is NSNull) {
            guard let text = error as? String else { throw MathpixUsageError.malformed }
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw MathpixUsageError.serviceRejected
            }
        }
        if let info = json["error_info"], !(info is NSNull) {
            guard let object = info as? [String: Any] else { throw MathpixUsageError.malformed }
            if !object.isEmpty { throw MathpixUsageError.serviceRejected }
        }
        guard let response = try? JSONDecoder().decode(UsageResponse.self, from: data) else {
            throw MathpixUsageError.malformed
        }
        // The official SDK documents a paginated endpoint. A full page cannot prove
        // completeness; never display a possibly truncated subtotal as monthly usage.
        guard response.ocr_usage.count < pageSize else { throw MathpixUsageError.incomplete }
        var count = 0
        for record in response.ocr_usage {
            guard record.count >= 0 else { throw MathpixUsageError.malformed }
            guard record.app_id == appID,
                  record.usage_type == "image" || record.usage_type == "image-async" else { continue }
            let (sum, overflow) = count.addingReportingOverflow(record.count)
            guard !overflow else { throw MathpixUsageError.malformed }
            count = sum
        }
        let period = try month(containing: now)
        return MathpixUsageSnapshot(appID: appID, imageCount: count, periodStart: period.start,
                                    periodEnd: period.end, fetchedAt: now)
    }

    private static func month(containing date: Date) throws -> DateInterval {
        guard date.timeIntervalSinceReferenceDate.isFinite else { throw MathpixUsageError.malformed }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let period = calendar.dateInterval(of: .month, for: date) else {
            throw MathpixUsageError.malformed
        }
        return period
    }

    private struct UsageResponse: Decodable {
        let ocr_usage: [UsageRecord]
    }

    private struct UsageRecord: Decodable {
        let app_id: String
        let usage_type: String
        let count: Int
    }
}
