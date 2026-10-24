import Foundation

/// A locally recorded Billing observation, not an authoritative API allowance.
/// Values are decimal strings so neither JSON nor binary floating point rounds money.
struct MathpixCreditEstimate: Codable, Equatable {
    let creditUSD: String
    let pendingUSD: String
    let imagePriceUSD: String
    let observedAt: Date

    private static let microsPerDollar: Int64 = 1_000_000
    private static let microsPerCent: Int64 = 10_000
    private static let maximumBalanceMicros: Int64 = 1_000_000 * microsPerDollar
    private static let maximumImagePriceMicros: Int64 = 1_000 * microsPerDollar

    init?(creditUSD: String, pendingUSD: String, imagePriceUSD: String = "0.002", observedAt: Date = Date()) {
        guard let credit = Self.parse(creditUSD, fractionalDigits: 2),
              let pending = Self.parse(pendingUSD, fractionalDigits: 2),
              let price = Self.parse(imagePriceUSD, fractionalDigits: 6),
              credit <= Self.maximumBalanceMicros,
              pending <= Self.maximumBalanceMicros,
              price > 0, price <= Self.maximumImagePriceMicros,
              observedAt.timeIntervalSinceReferenceDate.isFinite else { return nil }
        self.creditUSD = Self.formatCents(credit)
        self.pendingUSD = Self.formatCents(pending)
        self.imagePriceUSD = Self.formatPrice(price)
        self.observedAt = observedAt
    }

    /// Reserve a complete extra cent for the displayed pending charge's precision.
    /// Subsequent local image charges retain their exact microdollar precision.
    func reservedCostUSD(additionalRequests: Int) -> String? {
        guard let reserve = reservedMicros(additionalRequests: additionalRequests) else { return nil }
        return Self.formatMicros(reserve, minimumFractionalDigits: 2)
    }

    /// Round the Billing-based allowance down once, then deduct one for each
    /// local request. Exhausted credit returns zero, including very large counts.
    func remainingImages(additionalRequests: Int) -> Int? {
        guard additionalRequests >= 0,
              let count = Int64(exactly: additionalRequests),
              let credit = Self.parse(creditUSD, fractionalDigits: 2),
              let price = Self.parse(imagePriceUSD, fractionalDigits: 6),
              let reserve = reservedMicros(additionalRequests: 0) else { return nil }
        guard credit > reserve else { return 0 }
        let baselineCount = (credit - reserve) / price
        return baselineCount > count ? Int(exactly: baselineCount - count) : 0
    }

    /// Apply once when establishing a Billing baseline. If known monthly image
    /// usage already costs more than pending plus its precision margin, reserve
    /// that higher cost rounded up to cents, expressed as whole image debits.
    /// Subsequent local requests still deduct exactly one image each.
    func precisionDebitsForKnownMonthlyImages(_ count: Int) -> Int? {
        guard count >= 0,
              let images = Int64(exactly: count),
              let price = Self.parse(imagePriceUSD, fractionalDigits: 6),
              let baseline = reservedMicros(additionalRequests: 0) else { return nil }
        let (knownCost, costOverflow) = images.multipliedReportingOverflow(by: price)
        guard !costOverflow else { return nil }
        let wholeCents = knownCost / Self.microsPerCent
        let (roundedCents, roundOverflow) = wholeCents.addingReportingOverflow(knownCost % Self.microsPerCent == 0 ? 0 : 1)
        guard !roundOverflow else { return nil }
        let (upperCost, upperOverflow) = roundedCents.multipliedReportingOverflow(by: Self.microsPerCent)
        guard !upperOverflow else { return nil }
        guard upperCost > baseline else { return 0 }
        let excess = upperCost - baseline
        let wholeDebits = excess / price
        let (debits, debitOverflow) = wholeDebits.addingReportingOverflow(excess % price == 0 ? 0 : 1)
        return debitOverflow ? nil : Int(exactly: debits)
    }

    private func reservedMicros(additionalRequests: Int) -> Int64? {
        guard additionalRequests >= 0,
              let count = Int64(exactly: additionalRequests),
              let price = Self.parse(imagePriceUSD, fractionalDigits: 6),
              let pending = Self.parse(pendingUSD, fractionalDigits: 2) else { return nil }
        let (cost, costOverflow) = count.multipliedReportingOverflow(by: price)
        guard !costOverflow else { return nil }
        let (withMargin, marginOverflow) = pending.addingReportingOverflow(Self.microsPerCent)
        let (reserve, sumOverflow) = withMargin.addingReportingOverflow(cost)
        return marginOverflow || sumOverflow ? nil : reserve
    }

    /// Accept ASCII decimal notation only. The six-decimal internal unit is exact.
    private static func parse(_ input: String, fractionalDigits: Int) -> Int64? {
        guard !input.isEmpty, input.utf8.count <= 24 else { return nil }
        let bytes = Array(input.utf8)
        var whole: Int64 = 0
        var fraction: Int64 = 0
        var wholeDigits = 0
        var fractionCount = 0
        var hasPoint = false
        for byte in bytes {
            if byte == 46 {
                guard !hasPoint, wholeDigits > 0 else { return nil }
                hasPoint = true
                continue
            }
            guard (48...57).contains(byte) else { return nil }
            let digit = Int64(byte - 48)
            if hasPoint {
                fractionCount += 1
                guard fractionCount <= fractionalDigits else { return nil }
                fraction = fraction * 10 + digit
            } else {
                wholeDigits += 1
                let (multiplied, multiplyOverflow) = whole.multipliedReportingOverflow(by: 10)
                let (added, addOverflow) = multiplied.addingReportingOverflow(digit)
                guard !multiplyOverflow, !addOverflow else { return nil }
                whole = added
            }
        }
        guard wholeDigits > 0, !hasPoint || fractionCount > 0 else { return nil }
        for _ in fractionCount..<6 { fraction *= 10 }
        let (wholeMicros, multiplyOverflow) = whole.multipliedReportingOverflow(by: microsPerDollar)
        let (micros, addOverflow) = wholeMicros.addingReportingOverflow(fraction)
        return multiplyOverflow || addOverflow ? nil : micros
    }

    private static func formatCents(_ micros: Int64) -> String {
        formatMicros(micros, minimumFractionalDigits: 2)
    }

    private static func formatPrice(_ micros: Int64) -> String {
        formatMicros(micros, minimumFractionalDigits: 0)
    }

    private static func formatMicros(_ micros: Int64, minimumFractionalDigits: Int) -> String {
        let fraction = String(micros % microsPerDollar)
        var padded = String(repeating: "0", count: 6 - fraction.count) + fraction
        while padded.count > minimumFractionalDigits, padded.last == "0" { padded.removeLast() }
        return String(micros / microsPerDollar) + (padded.isEmpty ? "" : "." + padded)
    }

    private enum CodingKeys: String, CodingKey { case creditUSD, pendingUSD, imagePriceUSD, observedAt }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let credit = try values.decode(String.self, forKey: .creditUSD)
        let pending = try values.decode(String.self, forKey: .pendingUSD)
        let price = try values.decode(String.self, forKey: .imagePriceUSD)
        let date = try values.decode(Date.self, forKey: .observedAt)
        guard let validated = Self(creditUSD: credit, pendingUSD: pending, imagePriceUSD: price, observedAt: date) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid Mathpix credit estimate"))
        }
        self = validated
    }
}
