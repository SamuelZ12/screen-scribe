import Foundation
import CryptoKit

@main struct MathpixCreditStoreTests {
    @MainActor
    static func main() throws {
        let suite = "screenscribe.tests.credit.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let accountA = "fake-credit-account-A"
        let accountB = "fake-credit-account-B"
        let store = MathpixCreditStore(defaults: defaults)

        require(store.estimate == nil && store.remainingImages == nil, "there is no fabricated default credit")
        require(store.statusText == "总剩余：未设置" && store.detailText.contains("先保存"), "an unconfigured estimate does not present a numerical allowance")
        require(!store.save(creditUSD: "10.00", pendingUSD: "0.03", observedAt: date), "a snapshot requires a selected account")
        require(!store.recordAttempt(appID: accountA), "no snapshot means there is no baseline to debit")

        store.selectAccount(appID: " \(accountA) ")
        require(store.estimate == nil && store.detailText.contains("尚未设置账单快照"), "a selected account needs an explicit Billing observation")
        require(store.save(creditUSD: "10.00", pendingUSD: "0.03", observedAt: date), "valid currency saves for the selected account")
        require(store.estimate?.observedAt == date && store.additionalRequests == 0, "new snapshots retain their observed time and start a fresh local counter")
        require(store.remainingImages == 4_980 && store.statusText == "总剩余约 4980 次", "the model reserves the pending charge plus a cent")
        require(store.detailText.contains("非实时余额") && store.detailText.contains("$0.002/张"), "the detail explains that the displayed estimate is neither live nor universal")
        require(store.detailText.contains("可覆盖次数向下取整") && store.detailText.contains("每次请求扣 1 次"), "the rounding and per-image debit policies are visible")
        require(store.detailText.contains("统计可能延迟") && store.detailText.contains("其他设备") && store.detailText.contains("其他接口消费需更新快照"), "unobserved consumption and billing latency remain explicit")
        require(!store.detailText.contains(accountA), "details do not expose the raw account identifier")

        require(!store.save(creditUSD: "10.001", pendingUSD: "0.03", observedAt: date), "malformed Billing precision cannot replace a snapshot")
        require(!store.save(creditUSD: "10.00", pendingUSD: "-1", observedAt: date), "negative pending charges cannot increase the displayed balance")
        require(!store.save(creditUSD: "10.00", pendingUSD: "0.03", imagePriceUSD: "0", observedAt: date), "a zero price is invalid")
        require(store.remainingImages == 4_980 && store.additionalRequests == 0, "invalid edits leave the previous valid estimate intact")

        require(store.recordAttempt(appID: accountA), "a real request start records one reserve")
        require(store.additionalRequests == 1 && store.remainingImages == 4_979, "each image request debits one estimated image")
        require(store.detailText.contains("本机新增 1 次") && store.detailText.contains("当前共预留 $0.042"), "the detail exposes the exact local debit and the conservative base reserve")
        for _ in 0..<4 { require(store.recordAttempt(appID: accountA), "additional image attempts are recorded") }
        require(store.additionalRequests == 5 && store.remainingImages == 4_975, "five image starts debit exactly five images")
        require(store.recordAttempt(appID: accountA), "the sixth image is recorded")
        require(store.additionalRequests == 6 && store.remainingImages == 4_974, "the sixth image also debits only one")
        require(!store.recordAttempt(appID: accountB) && !store.recordAttempt(appID: "\(accountA)\n"), "other accounts and invalid identifiers cannot debit the selected estimate")
        require(store.additionalRequests == 6, "rejected attempts do not alter accounting")
        store.selectAccount(appID: accountA)
        require(store.additionalRequests == 6 && store.remainingImages == 4_974, "selecting the same account does not reset its counter")
        for index in 1...6 {
            require(store.recordCompletion(appID: accountA) == (index == 5), "only every fifth completed image asks the caller to calibrate")
        }
        require(store.completionRemainder == 1, "a partial batch remains after the fifth completion")
        require(!store.recordCompletion(appID: accountB), "an old account completion cannot advance the current batch")

        let restored = MathpixCreditStore(defaults: defaults)
        restored.selectAccount(appID: accountA)
        require(restored.estimate == store.estimate && restored.additionalRequests == 6 && restored.remainingImages == 4_974 && restored.completionRemainder == 1, "restart restores the observation, debits and completion-batch remainder")
        store.clearAccount()
        require(store.estimate == nil && store.remainingImages == nil && store.additionalRequests == 0, "clearing selection removes active account data from memory")
        store.selectAccount(appID: accountB)
        require(store.estimate == nil && store.remainingImages == nil, "a second account cannot inherit the first balance")
        require(!store.recordAttempt(appID: accountA), "a delayed old-account request cannot debit the new account")
        require(store.save(creditUSD: "3.00", pendingUSD: "0.00", imagePriceUSD: "0.003", observedAt: date), "different accounts may use different ordinary-image prices")
        require(store.recordAttempt(appID: accountB), "the second account records independently")
        require(store.remainingImages == 995, "per-account pricing feeds the same exact rounding model")
        store.selectAccount(appID: accountA)
        require(store.remainingImages == 4_974 && store.additionalRequests == 6 && store.completionRemainder == 1, "switching back restores the correct debit history and completion remainder")
        store.selectAccount(appID: "invalid\naccount")
        require(store.estimate == nil && store.remainingImages == nil, "invalid account input clears the visible estimate")
        store.selectAccount(appID: "\t")
        require(store.estimate == nil, "empty identifiers never form a persistence scope")
        store.selectAccount(appID: accountA)
        let later = date.addingTimeInterval(3_600)
        require(store.save(estimate: MathpixCreditEstimate(creditUSD: "8.00", pendingUSD: "0.06", observedAt: later)!), "an explicit updated Billing observation replaces the baseline")
        require(store.additionalRequests == 0 && store.remainingImages == 3_965 && store.estimate?.observedAt == later, "only saving a new snapshot resets request accounting")

        let domain = defaults.persistentDomain(forName: suite) ?? [:]
        require(domain.count == 2, "only a snapshot record for each account is persisted")
        require(domain.keys.allSatisfy { $0.hasPrefix("physics.mathpix.creditEstimate.") && $0.count == "physics.mathpix.creditEstimate.".count + 64 }, "account scopes use stable SHA256 keys")
        require(!String(describing: domain).contains("fake-credit-account"), "raw App IDs do not enter preference keys")
        for value in domain.values {
            let data = value as! Data
            let content = String(decoding: data, as: UTF8.self)
            require(!content.contains("fake-credit-account") && !content.lowercased().contains("apikey"), "persisted records contain only currency observations and counters")
        }

        store.clearEstimate()
        require(store.estimate == nil && store.remainingImages == nil && defaults.data(forKey: key(accountA)) == nil, "clear estimate removes this account's persisted baseline")
        let afterClear = MathpixCreditStore(defaults: defaults)
        afterClear.selectAccount(appID: accountA)
        require(afterClear.estimate == nil, "a removed estimate cannot reappear after restart")
        afterClear.selectAccount(appID: accountB)
        require(afterClear.additionalRequests == 1 && afterClear.remainingImages == 995, "deleting one estimate preserves the other account")

        let fixture = MathpixCreditEstimate(creditUSD: "20.00", pendingUSD: "0.00", observedAt: date)!
        defaults.set(try JSONEncoder().encode(StoredRecord(estimate: fixture, additionalRequests: Int.max, counterOverflowed: false)), forKey: key(accountA))
        let overflowing = MathpixCreditStore(defaults: defaults)
        overflowing.selectAccount(appID: accountA)
        require(overflowing.remainingImages == 0, "a very large count safely exhausts the available images")
        require(overflowing.recordAttempt(appID: accountA) && overflowing.counterOverflowed, "counter overflow is recorded rather than wrapping")
        require(overflowing.additionalRequests == Int.max && overflowing.remainingImages == 0, "overflow cannot create a new positive allowance")
        require(overflowing.detailText.contains("超出范围"), "overflow has an actionable explanation")
        let overflowRestored = MathpixCreditStore(defaults: defaults)
        overflowRestored.selectAccount(appID: accountA)
        require(overflowRestored.counterOverflowed && overflowRestored.remainingImages == 0, "overflow safety survives restart")
        require(overflowRestored.save(estimate: fixture) && !overflowRestored.counterOverflowed && overflowRestored.additionalRequests == 0, "a new explicit baseline clears exhausted local accounting")

        defaults.set(try JSONEncoder().encode(StoredRecord(estimate: fixture, additionalRequests: -1, counterOverflowed: false)), forKey: key(accountA))
        let corrupted = MathpixCreditStore(defaults: defaults)
        corrupted.selectAccount(appID: accountA)
        require(corrupted.estimate == nil && corrupted.remainingImages == nil, "negative persisted counts cannot increase credit")
        defaults.set(Data("not-json".utf8), forKey: key(accountA))
        let malformed = MathpixCreditStore(defaults: defaults)
        malformed.selectAccount(appID: accountA)
        require(malformed.estimate == nil && malformed.remainingImages == nil, "malformed local records never become a zero-cost estimate")
        var damaged = try JSONSerialization.jsonObject(with: JSONEncoder().encode(StoredRecord(estimate: fixture, additionalRequests: 1, counterOverflowed: false))) as! [String: Any]
        var damagedEstimate = damaged["estimate"] as! [String: Any]
        damagedEstimate["imagePriceUSD"] = "0"
        damaged["estimate"] = damagedEstimate
        defaults.set(try JSONSerialization.data(withJSONObject: damaged), forKey: key(accountA))
        let invalidMoney = MathpixCreditStore(defaults: defaults)
        invalidMoney.selectAccount(appID: accountA)
        require(invalidMoney.estimate == nil, "snapshot Codable validation also protects preference loading")
        require(invalidMoney.save(creditUSD: "0.01", pendingUSD: "0.05", observedAt: date), "exhausted balances are still valid observations")
        require(invalidMoney.remainingImages == 0 && invalidMoney.statusText == "总剩余约 0 次", "an observed zero allowance is distinct from an unset estimate")

        let calibration = MathpixCreditStore(defaults: defaults)
        let accountC = "fake-credit-account-C"
        let october = ISO8601DateFormatter().date(from: "2026-10-01T00:00:00Z")!
        let november = ISO8601DateFormatter().date(from: "2026-11-01T00:00:00Z")!
        let december = ISO8601DateFormatter().date(from: "2026-12-01T00:00:00Z")!
        calibration.selectAccount(appID: accountC)
        require(calibration.save(creditUSD: "100.00", pendingUSD: "0.00", observedAt: date), "the calibration scenario has an explicit independent baseline")
        require(calibration.remainingImages == 49_995 && !calibration.hasUsageBaseline, "Billing alone does not invent an official usage baseline")
        require(!calibration.setUsageBaseline(imageCount: -1, periodStart: october), "negative official image counts are invalid")
        require(!calibration.setUsageBaseline(imageCount: 100, periodStart: october.addingTimeInterval(1)), "only exact UTC month boundaries identify official periods")
        require(calibration.setUsageBaseline(imageCount: 0, periodStart: october), "the current month's genuine image count establishes calibration")
        for _ in 0..<5 { require(calibration.recordAttempt(appID: accountC), "each local attempt debits before server calibration") }
        require(calibration.remainingImages == 49_990, "local requests are visible immediately")
        require(calibration.reconcileUsage(imageCount: 3, periodStart: october), "a delayed official report can be reconciled")
        require(calibration.accountedRequests == 5 && calibration.remainingImages == 49_990, "delayed reporting cannot restore images or double-charge local images")
        require(calibration.reconcileUsage(imageCount: 8, periodStart: october), "other-client consumption can increase the server high water")
        require(calibration.additionalRequests == 5 && calibration.accountedRequests == 8 && calibration.remainingImages == 49_987, "official consumption above local starts calibrates the difference")
        require(calibration.recordAttempt(appID: accountC) && calibration.remainingImages == 49_986, "a local image still debits exactly one after external consumption was calibrated")
        require(calibration.reconcileUsage(imageCount: 9, periodStart: october) && calibration.remainingImages == 49_986, "the server catching up with this local image does not debit it twice")
        require(calibration.reconcileUsage(imageCount: 5, periodStart: october) && calibration.remainingImages == 49_986, "a regressing server report cannot increase the estimate")
        require(calibration.setUsageBaseline(imageCount: 9, periodStart: october) && calibration.remainingImages == 49_986, "re-establishing a baseline cannot erase prior debits")

        let calibrationRestored = MathpixCreditStore(defaults: defaults)
        calibrationRestored.selectAccount(appID: accountC)
        require(calibrationRestored.hasUsageBaseline && calibrationRestored.accountedRequests == 9 && calibrationRestored.remainingImages == 49_986, "the official high-water state survives restart")
        require(calibrationRestored.reconcileUsage(imageCount: 2, periodStart: november), "a new official month carries forward confirmed older consumption")
        require(calibrationRestored.accountedRequests == 11 && calibrationRestored.remainingImages == 49_984, "the monthly reset cannot refill total credit")
        require(calibrationRestored.needsBillingUpdate && calibrationRestored.statusText == "总剩余待更新账单" && !calibrationRestored.statusText.contains("49984") && calibrationRestored.detailText.contains("月末未同步消费可能遗漏"), "a cross-month estimate requests new Billing rather than presenting an unverified remaining number")
        require(calibrationRestored.reconcileUsage(imageCount: 4, periodStart: november) && calibrationRestored.accountedRequests == 13, "later counts in the new month add only their growth")
        require(calibrationRestored.reconcileUsage(imageCount: 4, periodStart: november) && calibrationRestored.accountedRequests == 13, "a repeated monthly report is idempotent")
        require(!calibrationRestored.reconcileUsage(imageCount: 500, periodStart: october) && calibrationRestored.accountedRequests == 13, "a late previous-month reply cannot corrupt the active period")
        require(calibrationRestored.recordAttempt(appID: accountC) && calibrationRestored.accountedRequests == 14, "local debits stay incremental across a month boundary")
        require(calibrationRestored.reconcileUsage(imageCount: 5, periodStart: november) && calibrationRestored.accountedRequests == 14, "new-month official reporting still avoids charging local images twice")
        require(calibrationRestored.reconcileUsage(imageCount: 1, periodStart: december) && calibrationRestored.accountedRequests == 15, "multiple month changes carry each confirmed delta exactly once")
        require(calibrationRestored.reconcileUsage(imageCount: Int.max, periodStart: december) && calibrationRestored.counterOverflowed && calibrationRestored.remainingImages == 0, "server cumulative overflow conservatively exhausts the estimate")
        require(calibrationRestored.save(estimate: fixture) && !calibrationRestored.needsBillingUpdate && !calibrationRestored.hasUsageBaseline && calibrationRestored.additionalRequests == 0 && calibrationRestored.accountedRequests == 0, "a fresh Billing observation resets all calibration state together")
        require(calibrationRestored.reconcileUsage(imageCount: 0, periodStart: december) && calibrationRestored.accountedRequests == 0, "a first usage observation establishes a baseline instead of charging pre-snapshot history")

        var invalidBaseline = try JSONSerialization.jsonObject(with: defaults.data(forKey: key(accountC))!) as! [String: Any]
        var baseline = invalidBaseline["usageBaseline"] as! [String: Any]
        baseline["highWaterCount"] = -1
        invalidBaseline["usageBaseline"] = baseline
        defaults.set(try JSONSerialization.data(withJSONObject: invalidBaseline), forKey: key(accountC))
        let invalidScope = MathpixCreditStore(defaults: defaults)
        invalidScope.selectAccount(appID: accountC)
        require(invalidScope.estimate == nil, "a damaged server high-water record cannot restore an overstated estimate")

        let precision = MathpixCreditStore(defaults: defaults)
        precision.selectAccount(appID: "fake-credit-account-precision")
        require(precision.save(creditUSD: "10.00", pendingUSD: "0.04", observedAt: date), "the precision scenario starts from cents reported by Billing")
        require(precision.recordAttempt(appID: "fake-credit-account-precision") && precision.recordAttempt(appID: "fake-credit-account-precision"), "local requests may precede the first official usage read")
        require(precision.remainingImages == 4_973, "before a baseline, only explicit local requests reduce the base estimate")
        require(precision.setUsageBaseline(imageCount: 35, periodStart: october), "known image charges can reveal a Billing delay or precision gap")
        require(precision.additionalRequests == 2 && precision.accountedRequests == 12 && precision.remainingImages == 4_963, "a two-cent precision gap adds ten reserved images without erasing local requests")
        require(precision.detailText.contains("初始账单延迟或精度差额额外预留 10 次"), "the precision debit is visible in the estimate explanation")
        require(precision.reconcileUsage(imageCount: 37, periodStart: october) && precision.accountedRequests == 12, "delayed reporting of two existing local requests cannot consume or cancel the precision reserve")
        require(precision.recordAttempt(appID: "fake-credit-account-precision") && precision.remainingImages == 4_962, "requests after the initial precision reserve still debit exactly one")
        require(precision.reconcileUsage(imageCount: 38, periodStart: october) && precision.accountedRequests == 13, "official catch-up remains idempotent when precision debits exist")
        require(precision.reconcileUsage(imageCount: 45, periodStart: october) && precision.accountedRequests == 20, "new server consumption is added above the retained precision reserve")
        require(precision.setUsageBaseline(imageCount: 45, periodStart: october) && precision.accountedRequests == 20, "repeated baseline calls cannot repeatedly add the same precision reserve")
        let precisionRestored = MathpixCreditStore(defaults: defaults)
        precisionRestored.selectAccount(appID: "fake-credit-account-precision")
        require(precisionRestored.accountedRequests == 20 && precisionRestored.reconcileUsage(imageCount: 45, periodStart: october) && precisionRestored.accountedRequests == 20, "precision debits and their server baseline survive restart")
        require(precisionRestored.reconcileUsage(imageCount: 1, periodStart: november) && precisionRestored.accountedRequests == 21, "cross-month carrying adds the precision reserve exactly once")

        // The previous store schema did not include precisionDebits. Loading it
        // preserves accounting with a zero default rather than losing the record.
        let precisionKey = key("fake-credit-account-precision")
        var legacy = try JSONSerialization.jsonObject(with: defaults.data(forKey: precisionKey)!) as! [String: Any]
        var legacyBaseline = legacy["usageBaseline"] as! [String: Any]
        legacyBaseline.removeValue(forKey: "precisionDebits")
        legacy["usageBaseline"] = legacyBaseline
        defaults.set(try JSONSerialization.data(withJSONObject: legacy), forKey: precisionKey)
        let legacyRestored = MathpixCreditStore(defaults: defaults)
        legacyRestored.selectAccount(appID: "fake-credit-account-precision")
        require(legacyRestored.estimate != nil && legacyRestored.accountedRequests == 21, "the initial preference schema remains readable")

        let precisionOverflow = MathpixCreditStore(defaults: defaults)
        precisionOverflow.selectAccount(appID: "fake-credit-account-precision-overflow")
        require(precisionOverflow.save(creditUSD: "10.00", pendingUSD: "0.00", observedAt: date), "overflow checks use a valid baseline")
        require(precisionOverflow.setUsageBaseline(imageCount: Int.max, periodStart: october) && precisionOverflow.counterOverflowed && precisionOverflow.remainingImages == 0, "unrepresentable initial precision charges fail closed")

        print("MathpixCreditStoreTests passed: explicit Billing snapshots, account isolation, per-image persistent debits, every-five completion batches, precision margin, server high-water reconciliation, month carry, restart and safe corrupt/overflow states")
    }

    private struct StoredRecord: Codable {
        let estimate: MathpixCreditEstimate
        let additionalRequests: Int
        let accountedRequests: Int
        let completionRemainder: Int
        let counterOverflowed: Bool
        let needsBillingUpdate: Bool

        init(estimate: MathpixCreditEstimate, additionalRequests: Int, counterOverflowed: Bool) {
            self.estimate = estimate
            self.additionalRequests = additionalRequests
            self.accountedRequests = max(0, additionalRequests)
            self.completionRemainder = 0
            self.counterOverflowed = counterOverflowed
            self.needsBillingUpdate = false
        }
    }

    private static func key(_ appID: String) -> String {
        let scope = SHA256.hash(data: Data(appID.utf8)).map { String(format: "%02x", $0) }.joined()
        return "physics.mathpix.creditEstimate.\(scope)"
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
    }
}
