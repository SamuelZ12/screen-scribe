import Foundation

@main struct MathpixUsageStoreTests {
    @MainActor
    static func main() async throws {
        let suite = "screenscribe.tests.usage.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let clock = Clock(date("2026-10-24T07:00:00Z"))
        let replies = Replies()
        let store = MathpixUsageStore(defaults: defaults, now: { clock.value }, fetch: replies.fetch)
        let accountA = configuration("fake-app-A")
        let accountB = configuration("fake-app-B")

        expect(store.monthlyBudget == 0 && store.snapshot == nil, "there is no fabricated global allowance")
        expect(!store.statusText.contains("剩余"), "no remaining number is shown before a genuine query")
        store.selectAccount(appID: accountA.appID)
        expect(store.monthlyBudget == 0, "new accounts have no implicit 2000 default")
        store.setMonthlyBudget(2000)
        store.clearAccount()
        expect(store.monthlyBudget == 0 && store.snapshot == nil, "clear removes account data from memory")
        store.selectAccount(appID: accountB.appID)
        expect(store.monthlyBudget == 0, "a second account does not inherit the first budget")
        store.setMonthlyBudget(500)
        store.selectAccount(appID: accountA.appID)
        expect(store.monthlyBudget == 2000, "switching back restores only this account's budget")
        let restored = MathpixUsageStore(defaults: defaults, now: { clock.value }, fetch: replies.fetch)
        restored.selectAccount(appID: accountB.appID)
        expect(restored.monthlyBudget == 500 && restored.snapshot == nil, "budget persists without persisting usage data")
        restored.setMonthlyBudget(-1)
        expect(restored.monthlyBudget == 0, "negative budgets become unset")
        restored.setMonthlyBudget(500)

        store.refresh(configuration: accountA)
        expect(store.refreshing && store.statusText == "正在查询本月用量…", "first refresh honestly reports in-progress state")
        await waitUntil { replies.pending.count == 1 }
        replies.succeed(0, count: 98)
        await waitUntil { !store.refreshing }
        expect(store.snapshot?.imageCount == 98 && store.statusText == "本月剩余约 1902 次", "remaining comes from the server count and the account budget")
        expect(store.detailText.contains("2026-10") && store.detailText.contains("UTC"), "detail identifies the queried UTC month")
        expect(store.detailText.contains("统计可能延迟") && store.detailText.contains("填写的月上限 2000"), "detail explains the estimate and the supplied limit")
        expect(store.detailText.contains("2026-10-24 07:00:00"), "detail includes the snapshot update time")
        store.setMonthlyBudget(0)
        expect(store.statusText == "本月已用 98 次", "unset limits show actual usage without inventing a remaining allowance")
        store.setMonthlyBudget(50)
        expect(store.statusText == "本月剩余约 0 次", "exceeded budgets clamp at zero")
        store.setMonthlyBudget(2000)

        store.refresh(configuration: accountA)
        await waitUntil { replies.pending.count == 1 }
        replies.fail(1)
        await waitUntil { !store.refreshing }
        expect(store.snapshot?.imageCount == 98, "a failed query may retain the previous snapshot in memory")
        expect(store.statusText == "用量暂不可用 · 点击刷新" && !store.statusText.contains("1902"), "a failed refresh cannot present the old remaining count as current")
        expect(store.detailText.contains("上次数据待刷新") && !store.detailText.contains("sensitive-error"), "failure is fixed safe text with an honest stale label")
        expect(store.detailText.contains("用量查询失败，请稍后刷新或查看 Mathpix 控制台。"), "unknown errors use only a generic diagnosis")

        store.refresh(configuration: accountA)
        await waitUntil { replies.pending.count == 1 }
        replies.succeed(2, count: 99)
        await waitUntil { !store.refreshing }
        expect(store.statusText == "本月剩余约 1901 次", "a successful retry clears failure state")
        expect(!store.detailText.contains("查询失败"), "a successful refresh clears the previous failure diagnosis")
        clock.value = date("2026-11-01T00:00:00Z")
        expect(store.statusText == "本月用量待刷新", "a UTC month rollover invalidates the previous remaining number")
        expect(store.detailText.contains("已跨月"), "old monthly snapshots are explicitly marked")
        store.refresh(configuration: accountA)
        await waitUntil { replies.pending.count == 1 }
        replies.succeed(3, count: 3)
        await waitUntil { !store.refreshing }
        expect(store.statusText == "本月剩余约 1997 次" && store.detailText.contains("2026-11"), "a new month requires a new actual query")

        store.refresh(configuration: accountA)
        await waitUntil { replies.pending.count == 1 }
        store.selectAccount(appID: accountB.appID)
        expect(!store.refreshing && store.snapshot == nil && store.monthlyBudget == 500, "switching account immediately clears the previous usage and task state")
        store.refresh(configuration: accountB)
        await waitUntil { replies.pending.count == 2 }
        replies.succeed(4, count: 999)
        await drainTasks()
        expect(store.snapshot == nil && store.refreshing, "an old account's late reply cannot populate or finish the new account query")
        replies.succeed(5, count: 7)
        await waitUntil { !store.refreshing }
        expect(store.snapshot?.appID == accountB.appID && store.statusText == "本月剩余约 493 次", "only the selected account response is used")

        store.refresh(configuration: accountB)
        await waitUntil { replies.pending.count == 1 }
        store.refresh(configuration: accountB)
        await waitUntil { replies.pending.count == 2 }
        replies.succeed(7, count: 8)
        await waitUntil { !store.refreshing }
        replies.succeed(6, count: 900)
        await drainTasks()
        expect(store.snapshot?.imageCount == 8, "even within one account a cancelled older response cannot overwrite the latest query")

        store.refresh(configuration: accountB)
        await waitUntil { replies.pending.count == 1 }
        store.clearAccount()
        replies.succeed(8, count: 100)
        await drainTasks()
        expect(store.snapshot == nil && !store.refreshing && store.monthlyBudget == 0, "clear prevents pending tasks from reviving account information")

        for invalid in [configuration(""), configuration("fake-app-A", key: "  "), configuration("fake\ninjected"),
                        configuration("fake-app-A", key: "key\nvalue"), configuration("fake-app-A", backend: .openAI)] {
            store.refresh(configuration: invalid)
            await drainTasks()
            expect(replies.pending.isEmpty && store.snapshot == nil && !store.refreshing, "unsupported or invalid configurations never start a usage request")
        }
        expect(replies.nextID == 9, "only explicitly requested valid Mathpix queries were performed")

        let safeFailures: [(Error, String)] = [
            (MathpixUsageError.configuration, "配置不完整"),
            (MathpixUsageError.malformed, "用量响应格式不符合要求"),
            (MathpixUsageError.serviceRejected, "服务拒绝了用量查询"),
            (MathpixUsageError.incomplete, "用量数据可能不完整"),
            (RecognitionError.http(401), "HTTP 401：认证失败"),
            (RecognitionError.http(403), "HTTP 403：此凭据的用量查询访问被拒绝"),
            (RecognitionError.http(429), "HTTP 429：请求被限流或受到服务额度限制"),
            (RecognitionError.http(503), "HTTP 503：用量查询请求失败"),
            (RecognitionError.network, "网络连接失败或请求超时"),
            (RecognitionError.cancelled, "用量查询已取消"),
            (RecognitionError.malformed, "用量响应格式不符合要求"),
            (RecognitionError.configuration("sensitive-error fake-key-not-for-storage"), "用量查询失败，请稍后刷新或查看 Mathpix 控制台。"),
            (NSError(domain: "sensitive-error", code: 403, userInfo: [NSLocalizedDescriptionKey: "sensitive-error fake-key-not-for-storage"]), "用量查询失败，请稍后刷新或查看 Mathpix 控制台。")
        ]
        for (error, expected) in safeFailures {
            let errorStore = MathpixUsageStore(defaults: defaults, now: { clock.value }, fetch: { _, _ in throw error })
            errorStore.refresh(configuration: accountA)
            await waitUntil { !errorStore.refreshing }
            expect(errorStore.statusText == "用量暂不可用 · 点击刷新", "typed failures never become a zero usage result")
            expect(errorStore.detailText.contains(expected), "the allowlisted failure category provides a safe diagnostic")
            expect(!errorStore.detailText.contains("sensitive-error") && !errorStore.detailText.contains("fake-key-not-for-storage"), "neither error descriptions nor associated credential-bearing text are displayed")
            errorStore.clearAccount()
            expect(!errorStore.detailText.contains(expected), "clearing an account also removes its failure diagnosis")
        }

        let domain = defaults.persistentDomain(forName: suite) ?? [:]
        expect(domain.count == 2, "only one budget per selected account is persisted")
        let stored = String(describing: domain)
        expect(!stored.contains("fake-app") && !stored.contains("fake-key-not-for-storage"), "raw account identifiers and API keys never enter defaults")
        expect(domain.keys.allSatisfy { $0.hasPrefix("physics.mathpix.monthlyBudget.") && $0.count == "physics.mathpix.monthlyBudget.".count + 64 }, "budget scopes use a stable SHA256 digest")
        print("MathpixUsageStoreTests passed: account-scoped budgets, no secrets persisted, honest stale/UTC-month states, clamped estimates, cancelled and late replies, allowlisted safe failure diagnostics")
    }

    private static func configuration(_ appID: String, key: String = "fake-key-not-for-storage", backend: RecognitionBackend = .mathpix) -> RecognitionConfiguration {
        RecognitionConfiguration(backend: backend, model: "", baseURL: "", appID: appID, apiKey: key)
    }

    private static func date(_ string: String) -> Date { ISO8601DateFormatter().date(from: string)! }

    @MainActor private static func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<1000 {
            if condition() { return }
            await Task.yield()
        }
        fatalError("async test state did not arrive")
    }

    private static func drainTasks() async { for _ in 0..<20 { await Task.yield() } }

    @MainActor private final class Clock {
        var value: Date
        init(_ value: Date) { self.value = value }
    }

    @MainActor private final class Replies {
        struct Pending {
            let appID: String
            let date: Date
            let continuation: CheckedContinuation<MathpixUsageSnapshot, Error>
        }
        var pending: [Int: Pending] = [:]
        var nextID = 0

        func fetch(_ configuration: RecognitionConfiguration, _ date: Date) async throws -> MathpixUsageSnapshot {
            try await withCheckedThrowingContinuation { continuation in
                let id = nextID
                nextID += 1
                pending[id] = Pending(appID: configuration.appID, date: date, continuation: continuation)
            }
        }

        func succeed(_ id: Int, count: Int) {
            let request = pending.removeValue(forKey: id)!
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            let period = calendar.dateInterval(of: .month, for: request.date)!
            request.continuation.resume(returning: MathpixUsageSnapshot(appID: request.appID, imageCount: count,
                periodStart: period.start, periodEnd: period.end, fetchedAt: request.date))
        }

        func fail(_ id: Int) {
            pending.removeValue(forKey: id)!.continuation.resume(throwing: NSError(domain: "sensitive-error", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "sensitive-error fake-key-not-for-storage"]))
        }
    }
}
