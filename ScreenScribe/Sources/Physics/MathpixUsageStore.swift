import Foundation
import Combine
import CryptoKit

@MainActor
final class MathpixUsageStore: ObservableObject {
    typealias Fetch = (RecognitionConfiguration, Date) async throws -> MathpixUsageSnapshot
    static let shared = MathpixUsageStore()

    @Published private(set) var snapshot: MathpixUsageSnapshot?
    @Published private(set) var monthlyBudget = 0
    @Published private(set) var refreshing = false
    @Published private var failed = false
    @Published private var failureDetail = ""

    private let defaults: UserDefaults
    private let now: () -> Date
    private let fetch: Fetch
    private var appID: String?
    private var task: Task<Void, Never>?
    private var generation = UUID()

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init,
         fetch: @escaping Fetch = { configuration, date in
             try await MathpixUsageService(appID: configuration.appID, apiKey: configuration.apiKey).fetch(now: date)
         }) {
        self.defaults = defaults
        self.now = now
        self.fetch = fetch
    }

    func selectAccount(appID: String) {
        let selected = appID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selected.isEmpty, !appID.contains(where: { $0.isNewline }) else {
            clearAccount()
            return
        }
        guard self.appID != selected else { return }
        clearAccount()
        self.appID = selected
        monthlyBudget = max(0, defaults.integer(forKey: budgetKey(selected)))
    }

    func setMonthlyBudget(_ value: Int) {
        guard let appID else { return }
        monthlyBudget = max(0, value)
        defaults.set(monthlyBudget, forKey: budgetKey(appID))
    }

    func clearAccount() {
        generation = UUID()
        task?.cancel()
        task = nil
        appID = nil
        snapshot = nil
        monthlyBudget = 0
        refreshing = false
        failed = false
        failureDetail = ""
    }

    func refresh(configuration: RecognitionConfiguration, onSuccess: ((MathpixUsageSnapshot) -> Void)? = nil) {
        guard configuration.backend == .mathpix,
              !configuration.appID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !configuration.appID.contains(where: { $0.isNewline }),
              !configuration.apiKey.contains(where: { $0.isNewline }) else {
            clearAccount()
            return
        }
        selectAccount(appID: configuration.appID)
        guard let selected = appID else { return }
        task?.cancel()
        let token = UUID()
        generation = token
        let requestDate = now()
        var requestConfiguration = configuration
        requestConfiguration.appID = selected
        refreshing = true
        failed = false
        failureDetail = ""
        task = Task { [weak self, fetch] in
            do {
                let result = try await fetch(requestConfiguration, requestDate)
                try Task.checkCancellation()
                guard let self, self.generation == token, self.appID == selected else { return }
                guard result.appID == selected, result.imageCount >= 0,
                      Self.isCurrent(result, at: requestDate), result.fetchedAt.timeIntervalSinceReferenceDate.isFinite else {
                    throw MathpixUsageError.malformed
                }
                self.snapshot = result
                self.failed = false
                self.failureDetail = ""
                onSuccess?(result)
                self.finish(token)
            } catch {
                guard let self, self.generation == token, self.appID == selected else { return }
                // Neither provider responses nor credential-bearing errors reach the UI.
                self.failed = true
                self.failureDetail = Self.safeFailureDetail(error)
                self.finish(token)
            }
        }
    }

    var statusText: String {
        if refreshing { return "正在查询本月用量…" }
        if failed { return "用量暂不可用 · 点击刷新" }
        guard let snapshot, snapshot.appID == appID else { return "用量尚未查询" }
        guard Self.isCurrent(snapshot, at: now()) else { return "本月用量待刷新" }
        if monthlyBudget > 0 { return "本月剩余约 \(max(0, monthlyBudget - snapshot.imageCount)) 次" }
        return "本月已用 \(snapshot.imageCount) 次"
    }

    var detailText: String {
        var details = ["查询范围采用 UTC 自然月；Mathpix 用量统计可能延迟。"]
        if let snapshot, snapshot.appID == appID {
            details.append("查询月份：\(Self.format(snapshot.periodStart, pattern: "yyyy-MM"))（UTC）；更新时间：\(Self.format(snapshot.fetchedAt, pattern: "yyyy-MM-dd HH:mm:ss")) UTC。")
            if !Self.isCurrent(snapshot, at: now()) { details.append("上次数据已跨月，请点击刷新。") }
        }
        if monthlyBudget > 0 {
            details.append("剩余次数按你填写的月上限 \(monthlyBudget) 次计算。")
        } else {
            details.append("尚未填写月上限，查询成功后显示本月已用次数。")
        }
        if failed {
            details.append("查询失败，上次数据待刷新；可点击刷新重试。")
            details.append(failureDetail)
        }
        if appID == nil { details.append("请先保存有效的 Mathpix 配置。") }
        return details.joined(separator: "\n")
    }

    private func finish(_ token: UUID) {
        guard generation == token else { return }
        refreshing = false
        task = nil
    }

    private static func safeFailureDetail(_ error: Error) -> String {
        if let error = error as? MathpixUsageError {
            switch error {
            case .configuration: return "Mathpix 配置不完整，请重新保存 App ID 与 App Key。"
            case .malformed: return "Mathpix 用量响应格式不符合要求，请稍后刷新。"
            case .serviceRejected: return "Mathpix 服务拒绝了用量查询，请查看控制台或联系服务方。"
            case .incomplete: return "Mathpix 返回的用量数据可能不完整，请查看控制台。"
            }
        }
        if let error = error as? RecognitionError {
            switch error {
            case .http(401): return "HTTP 401：认证失败，请核对已保存的 Mathpix 凭据。"
            case .http(403): return "HTTP 403：此凭据的用量查询访问被拒绝，请确认查询权限或联系 Mathpix。"
            case .http(429): return "HTTP 429：请求被限流或受到服务额度限制，请稍后刷新并检查控制台。"
            case .http(let status): return "HTTP \(status)：用量查询请求失败，请稍后刷新或查看控制台。"
            case .network: return "网络连接失败或请求超时，请检查网络后刷新。"
            case .cancelled: return "用量查询已取消，可点击刷新重试。"
            case .malformed: return "用量响应格式不符合要求，请稍后刷新。"
            default: break
            }
        }
        return "用量查询失败，请稍后刷新或查看 Mathpix 控制台。"
    }

    private func budgetKey(_ appID: String) -> String {
        let scope = SHA256.hash(data: Data(appID.utf8)).map { String(format: "%02x", $0) }.joined()
        return "physics.mathpix.monthlyBudget.\(scope)"
    }

    private static func isCurrent(_ snapshot: MathpixUsageSnapshot, at date: Date) -> Bool {
        guard date.timeIntervalSinceReferenceDate.isFinite else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let period = calendar.dateInterval(of: .month, for: date) else { return false }
        return snapshot.periodStart == period.start && snapshot.periodEnd == period.end
    }

    private static func format(_ date: Date, pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}
