import Foundation
import Combine
import CryptoKit

/// A local estimate based on an explicitly recorded Billing snapshot. This does
/// not query Billing or treat the image-use/monthly-page counters as a balance.
@MainActor
final class MathpixCreditStore: ObservableObject {
    static let shared = MathpixCreditStore()

    @Published private(set) var estimate: MathpixCreditEstimate?
    @Published private(set) var additionalRequests = 0
    @Published private(set) var accountedRequests = 0
    @Published private(set) var completionRemainder = 0
    @Published private(set) var counterOverflowed = false
    @Published private(set) var needsBillingUpdate = false
    @Published private var usageBaseline: UsageBaseline?

    private let defaults: UserDefaults
    private var appID: String?

    private struct Record: Codable {
        let estimate: MathpixCreditEstimate
        var additionalRequests: Int
        var accountedRequests: Int
        var completionRemainder: Int
        var counterOverflowed: Bool
        var needsBillingUpdate: Bool
        var usageBaseline: UsageBaseline?
    }

    private struct UsageBaseline: Codable {
        var periodStart: Date
        var baseCount: Int
        var highWaterCount: Int
        var confirmedPriorPeriods: Int
        var precisionDebits: Int

        init(periodStart: Date, baseCount: Int, highWaterCount: Int,
             confirmedPriorPeriods: Int, precisionDebits: Int = 0) {
            self.periodStart = periodStart
            self.baseCount = baseCount
            self.highWaterCount = highWaterCount
            self.confirmedPriorPeriods = confirmedPriorPeriods
            self.precisionDebits = precisionDebits
        }

        private enum CodingKeys: String, CodingKey {
            case periodStart, baseCount, highWaterCount, confirmedPriorPeriods, precisionDebits
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            periodStart = try values.decode(Date.self, forKey: .periodStart)
            baseCount = try values.decode(Int.self, forKey: .baseCount)
            highWaterCount = try values.decode(Int.self, forKey: .highWaterCount)
            confirmedPriorPeriods = try values.decode(Int.self, forKey: .confirmedPriorPeriods)
            precisionDebits = try values.decodeIfPresent(Int.self, forKey: .precisionDebits) ?? 0
        }

        var isValid: Bool {
            MathpixCreditStore.validPeriod(periodStart) && baseCount >= 0 &&
                highWaterCount >= baseCount && confirmedPriorPeriods >= 0 && precisionDebits >= 0
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func selectAccount(appID: String) {
        guard let selected = Self.validAccount(appID) else {
            clearAccount()
            return
        }
        guard self.appID != selected else { return }
        clearAccount()
        self.appID = selected
        guard let data = defaults.data(forKey: storageKey(selected)),
              let record = try? JSONDecoder().decode(Record.self, from: data),
              record.additionalRequests >= 0,
              record.accountedRequests >= record.additionalRequests,
              (0..<5).contains(record.completionRemainder),
              record.usageBaseline?.isValid != false else { return }
        apply(record)
    }

    /// Clear only the active in-memory scope. Switching back restores its own
    /// snapshot and counter; another account never inherits these values.
    func clearAccount() {
        appID = nil
        estimate = nil
        additionalRequests = 0
        accountedRequests = 0
        completionRemainder = 0
        counterOverflowed = false
        needsBillingUpdate = false
        usageBaseline = nil
    }

    /// Saving means the user has observed a new Billing snapshot. Requests since
    /// the old snapshot are covered by that observation and start again at zero.
    @discardableResult
    func save(creditUSD: String, pendingUSD: String, imagePriceUSD: String = "0.002",
              observedAt: Date = Date()) -> Bool {
        guard let estimate = MathpixCreditEstimate(creditUSD: creditUSD, pendingUSD: pendingUSD,
                                                   imagePriceUSD: imagePriceUSD, observedAt: observedAt) else { return false }
        return save(estimate: estimate)
    }

    @discardableResult
    func save(estimate: MathpixCreditEstimate) -> Bool {
        guard let appID else { return false }
        let record = Record(estimate: estimate, additionalRequests: 0, accountedRequests: 0,
                            completionRemainder: 0, counterOverflowed: false,
                            needsBillingUpdate: false, usageBaseline: nil)
        guard persist(record, appID: appID) else { return false }
        apply(record)
        return true
    }

    func clearEstimate() {
        guard let appID else { return }
        defaults.removeObject(forKey: storageKey(appID))
        estimate = nil
        additionalRequests = 0
        accountedRequests = 0
        completionRemainder = 0
        counterOverflowed = false
        needsBillingUpdate = false
        usageBaseline = nil
    }

    /// Call once when a real image request starts, including failed requests and
    /// retries. A late request from a previously selected account cannot alter
    /// the current estimate. No snapshot means there is no baseline to debit.
    @discardableResult
    func recordAttempt(appID: String) -> Bool {
        guard let selected = Self.validAccount(appID), selected == self.appID,
              var record = currentRecord else { return false }
        let (next, overflow) = additionalRequests.addingReportingOverflow(1)
        let (accounted, accountedOverflow) = accountedRequests.addingReportingOverflow(1)
        record.additionalRequests = overflow ? Int.max : next
        record.accountedRequests = accountedOverflow ? Int.max : accounted
        record.counterOverflowed = counterOverflowed || overflow || accountedOverflow
        guard persist(record, appID: selected) else {
            // Never present a higher allowance after a local accounting error.
            counterOverflowed = true
            return false
        }
        apply(record)
        return true
    }

    /// Finishes one image attempt. The caller queries official image use only on
    /// every fifth completion. Keep the remainder across restart/account changes.
    @discardableResult
    func recordCompletion(appID: String) -> Bool {
        guard let selected = Self.validAccount(appID), selected == self.appID,
              var record = currentRecord else { return false }
        record.completionRemainder = (record.completionRemainder + 1) % 5
        guard persist(record, appID: selected) else { return false }
        apply(record)
        return record.completionRemainder == 0
    }

    /// Establish this when saving Billing and its current official image count.
    /// Repeated calls after a baseline exists reconcile instead of resetting it.
    @discardableResult
    func setUsageBaseline(imageCount: Int, periodStart: Date) -> Bool {
        guard imageCount >= 0, Self.validPeriod(periodStart), let appID,
              var record = currentRecord else { return false }
        if usageBaseline != nil { return reconcileUsage(imageCount: imageCount, periodStart: periodStart) }
        let precision = record.estimate.precisionDebitsForKnownMonthlyImages(imageCount)
        let (accounted, overflow) = record.accountedRequests.addingReportingOverflow(precision ?? Int.max)
        record.accountedRequests = overflow ? Int.max : accounted
        record.counterOverflowed = record.counterOverflowed || precision == nil || overflow
        record.usageBaseline = UsageBaseline(periodStart: periodStart, baseCount: imageCount,
                                             highWaterCount: imageCount, confirmedPriorPeriods: 0,
                                             precisionDebits: precision ?? Int.max)
        guard persist(record, appID: appID) else { return false }
        apply(record)
        return true
    }

    /// Official use can only increase debits. This avoids charging a local image
    /// a second time when the delayed usage report catches up with the app.
    @discardableResult
    func reconcileUsage(imageCount: Int, periodStart: Date) -> Bool {
        guard imageCount >= 0, Self.validPeriod(periodStart), let appID,
              var record = currentRecord else { return false }
        guard var baseline = record.usageBaseline else {
            return setUsageBaseline(imageCount: imageCount, periodStart: periodStart)
        }
        guard periodStart >= baseline.periodStart else { return false }
        if periodStart > baseline.periodStart {
            // Carry only confirmed older-period consumption. A new month cannot
            // restore credit, and an unobserved month-end still needs new Billing.
            let delta = baseline.highWaterCount - baseline.baseCount
            let (carry, overflow) = baseline.confirmedPriorPeriods.addingReportingOverflow(delta)
            baseline.confirmedPriorPeriods = overflow ? Int.max : carry
            baseline.periodStart = periodStart
            baseline.baseCount = 0
            baseline.highWaterCount = imageCount
            record.counterOverflowed = record.counterOverflowed || overflow
            record.needsBillingUpdate = true
        } else {
            baseline.highWaterCount = max(baseline.highWaterCount, imageCount)
        }
        let delta = baseline.highWaterCount - baseline.baseCount
        let (serverTotal, overflow) = baseline.confirmedPriorPeriods.addingReportingOverflow(delta)
        let (withPrecision, precisionOverflow) = serverTotal.addingReportingOverflow(baseline.precisionDebits)
        record.accountedRequests = max(record.accountedRequests, overflow || precisionOverflow ? Int.max : withPrecision)
        record.counterOverflowed = record.counterOverflowed || overflow || precisionOverflow
        record.usageBaseline = baseline
        guard persist(record, appID: appID) else { return false }
        apply(record)
        return true
    }

    var hasUsageBaseline: Bool { usageBaseline != nil }

    var remainingImages: Int? {
        guard let estimate else { return nil }
        guard !counterOverflowed else { return 0 }
        // Both integer-counter and money-arithmetic overflow fail closed.
        return estimate.remainingImages(additionalRequests: accountedRequests) ?? 0
    }

    var statusText: String {
        guard let remainingImages else { return "总剩余：未设置" }
        if needsBillingUpdate { return "总剩余待更新账单" }
        return "总剩余约 \(remainingImages) 次"
    }

    var detailText: String {
        guard let appID, !appID.isEmpty else { return "请先保存有效的 Mathpix 配置。" }
        guard let estimate else {
            return "尚未设置账单快照。请从 Mathpix Billing 填入抵扣余额、待结算费用及普通图片单价；此处不读取实时余额。"
        }
        var details = [
            "账单快照：\(Self.format(estimate.observedAt))；这是本地记录，非实时余额。",
            "抵扣余额 $\(estimate.creditUSD)，待结算 $\(estimate.pendingUSD)，普通图片单价 $\(estimate.imagePriceUSD)/张。",
            "待结算额外预留 $0.01，基础可覆盖次数向下取整；之后本机每次请求扣 1 次，包含失败及重试。",
            "快照后本机新增 \(additionalRequests) 次；经官方用量校准后累计扣减 \(accountedRequests) 次。"
        ]
        if let reserved = estimate.reservedCostUSD(additionalRequests: accountedRequests), !counterOverflowed {
            details.append("当前共预留 $\(reserved)。官方用量只追加扣减，延迟或回退的数据不会增加剩余。")
        } else {
            details.append("本地计数或金额计算超出范围，保守显示 0 次；请更新账单快照。")
        }
        if !hasUsageBaseline { details.append("尚未建立官方用量校准基准；目前只扣本机请求。") }
        if let usageBaseline, !counterOverflowed {
            details.append("累计扣减含初始账单延迟或精度差额额外预留 \(usageBaseline.precisionDebits) 次；此差额仅建立基准时计入，后续仍逐张扣减。")
        }
        if needsBillingUpdate { details.append("官方用量已跨月；沿用已确认扣减，不恢复额度。月末未同步消费可能遗漏，请更新账单快照。") }
        details.append("账单统计可能延迟；其他设备的图片消费在官方用量更新后校准，长文本图片差价和其他接口消费需更新快照。此数表示抵扣金可覆盖的普通图片次数。")
        return details.joined(separator: "\n")
    }

    private func persist(_ record: Record, appID: String) -> Bool {
        guard let data = try? JSONEncoder().encode(record) else { return false }
        defaults.set(data, forKey: storageKey(appID))
        return true
    }

    private var currentRecord: Record? {
        guard let estimate else { return nil }
        return Record(estimate: estimate, additionalRequests: additionalRequests,
                      accountedRequests: accountedRequests, completionRemainder: completionRemainder,
                      counterOverflowed: counterOverflowed, needsBillingUpdate: needsBillingUpdate,
                      usageBaseline: usageBaseline)
    }

    private func apply(_ record: Record) {
        estimate = record.estimate
        additionalRequests = record.additionalRequests
        accountedRequests = record.accountedRequests
        completionRemainder = record.completionRemainder
        counterOverflowed = record.counterOverflowed
        needsBillingUpdate = record.needsBillingUpdate
        usageBaseline = record.usageBaseline
    }

    private func storageKey(_ appID: String) -> String {
        let scope = SHA256.hash(data: Data(appID.utf8)).map { String(format: "%02x", $0) }.joined()
        return "physics.mathpix.creditEstimate.\(scope)"
    }

    private static func validAccount(_ appID: String) -> String? {
        let selected = appID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selected.isEmpty, !appID.contains(where: { $0.isNewline }),
              !selected.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { return nil }
        return selected
    }

    nonisolated private static func validPeriod(_ date: Date) -> Bool {
        guard date.timeIntervalSinceReferenceDate.isFinite else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.dateInterval(of: .month, for: date)?.start == date
    }

    private static func format(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss ZZZZZ"
        return formatter.string(from: date)
    }
}
