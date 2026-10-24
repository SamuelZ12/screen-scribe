import Foundation

@main struct MathpixCreditEstimateTests {
    static func main() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let estimate = MathpixCreditEstimate(creditUSD: "12.34", pendingUSD: "1.23", observedAt: now)!
        require(estimate.creditUSD == "12.34" && estimate.pendingUSD == "1.23", "preserve Billing cents")
        require(estimate.imagePriceUSD == "0.002", "default ordinary-image price is represented exactly")
        require(estimate.reservedCostUSD(additionalRequests: 0) == "1.24", "reserve an extra cent for the rounded pending charge")
        require(estimate.remainingImages(additionalRequests: 0) == 5_550, "divide exact net credit by the exact decimal image price")
        require(estimate.reservedCostUSD(additionalRequests: 1) == "1.242", "local requests retain the exact image price")
        require(estimate.remainingImages(additionalRequests: 1) == 5_549, "each local request deducts exactly one image")
        require(estimate.remainingImages(additionalRequests: 5) == 5_545, "five local requests deduct five images")
        require(estimate.reservedCostUSD(additionalRequests: 5) == "1.25", "exact cent costs retain two display digits")
        require(estimate.remainingImages(additionalRequests: 6) == 5_544, "crossing a cent boundary still deducts one image")
        require(estimate.reservedCostUSD(additionalRequests: 6) == "1.252", "costs do not step up to whole cents")
        require(estimate.remainingImages(additionalRequests: -1) == nil, "negative request counts are invalid")
        require(estimate.reservedCostUSD(additionalRequests: -1) == nil, "negative requests do not reduce reserved charges")
        require(estimate.reservedCostUSD(additionalRequests: Int.max) == nil, "multiplication overflow remains unknown")
        require(estimate.remainingImages(additionalRequests: Int.max) == 0, "a request count above the allowance safely exhausts it without multiplication")
        require(estimate.remainingImages(additionalRequests: 5_550) == 0, "an exactly exhausted allowance is zero")
        require(estimate.remainingImages(additionalRequests: 5_551) == 0, "overdrawn allowance cannot become negative")
        require(estimate.precisionDebitsForKnownMonthlyImages(0) == 0, "no known monthly images need no additional reserve")
        require(estimate.precisionDebitsForKnownMonthlyImages(619) == 0, "known monthly cost below the existing reserve is not counted twice")
        require(estimate.precisionDebitsForKnownMonthlyImages(620) == 0, "known monthly cost equal to the reserve adds no debit")
        require(estimate.precisionDebitsForKnownMonthlyImages(621) == 5, "cost beyond Billing precision reserves the next whole cent")
        require(estimate.precisionDebitsForKnownMonthlyImages(625) == 5, "an exact next-cent cost does not reserve a second cent")
        require(estimate.precisionDebitsForKnownMonthlyImages(626) == 10, "round known monthly cost upward at the following cent boundary")
        require(estimate.precisionDebitsForKnownMonthlyImages(-1) == nil, "negative monthly counts are invalid")
        require(estimate.precisionDebitsForKnownMonthlyImages(Int.max) == nil, "monthly cost multiplication overflow remains unknown")

        let fractional = MathpixCreditEstimate(creditUSD: "1.00", pendingUSD: "0", imagePriceUSD: "0.003", observedAt: now)!
        require(fractional.remainingImages(additionalRequests: 0) == 330, "a whole cent reserve applies even when pending displays zero")
        require(fractional.remainingImages(additionalRequests: 1) == 329, "local decrements do not reapply Billing rounding")
        require(fractional.precisionDebitsForKnownMonthlyImages(3) == 0, "rounding known costs to the existing cent needs no extra debit")
        require(fractional.precisionDebitsForKnownMonthlyImages(4) == 4, "extra reserve divided by price rounds the required debits upward")
        let uneven = MathpixCreditEstimate(creditUSD: "1.01", pendingUSD: "0", imagePriceUSD: "0.003", observedAt: now)!
        require(uneven.remainingImages(additionalRequests: 0) == 333, "the initial affordable count rounds down")
        require(uneven.remainingImages(additionalRequests: 1) == 332, "fractional initial remainder does not alter per-image decrements")
        let cheap = MathpixCreditEstimate(creditUSD: "1", pendingUSD: "0", imagePriceUSD: "0.000001", observedAt: now)!
        require(cheap.remainingImages(additionalRequests: 0) == 990_000, "six-decimal prices retain full precision")
        require(cheap.reservedCostUSD(additionalRequests: 1) == "0.010001", "microdollar costs survive display formatting")
        require(cheap.remainingImages(additionalRequests: 10_000) == 980_000, "exact cent local fees have no unnecessary extra cent")
        require(cheap.precisionDebitsForKnownMonthlyImages(10_001) == 10_000, "microdollar monthly costs round up exactly without floating point")
        require(cheap.precisionDebitsForKnownMonthlyImages(Int.max) == nil, "rounding a non-multiplication-overflowing monthly cost can still overflow safely")
        let exhausted = MathpixCreditEstimate(creditUSD: "0.01", pendingUSD: "0.01", observedAt: now)!
        require(exhausted.remainingImages(additionalRequests: 0) == 0, "pending above credit clamps to zero")
        require(exhausted.remainingImages(additionalRequests: 100) == 0, "additional charges cannot create negative output")
        require(MathpixCreditEstimate(creditUSD: "0", pendingUSD: "0", observedAt: now)!.remainingImages(additionalRequests: 0) == 0, "zero balance is a genuine zero")

        let normalized = MathpixCreditEstimate(creditUSD: "0002.3", pendingUSD: "00", imagePriceUSD: "001.500000", observedAt: now)!
        require(normalized.creditUSD == "2.30" && normalized.pendingUSD == "0.00" && normalized.imagePriceUSD == "1.5", "canonical strings preserve exact values")
        require(MathpixCreditEstimate(creditUSD: "1000000.00", pendingUSD: "1000000", imagePriceUSD: "1000", observedAt: now) != nil, "bounded maximum inputs remain valid")

        for value in ["", " ", " 1", "1 ", "-1", "+1", "1e2", "NaN", "nan", "Infinity", "inf", ".01", "1.", "1..0", "1,00", "$1", "１", "١", "0x1", "1_0", "1\n", "1.001", "1000000.01", "9223372036854775807", "99999999999999999999999999999999"] {
            require(MathpixCreditEstimate(creditUSD: value, pendingUSD: "0", observedAt: now) == nil, "reject malformed, imprecise, or excessive credit")
            require(MathpixCreditEstimate(creditUSD: "1", pendingUSD: value, observedAt: now) == nil, "reject malformed, imprecise, or excessive pending charges")
        }
        for value in ["0", "0.000000", "0.0000001", "-0.001", "1e-3", "NaN", "1.0000000", "1000.000001", "18446744073709551615", "", "0.002 "] {
            require(MathpixCreditEstimate(creditUSD: "1", pendingUSD: "0", imagePriceUSD: value, observedAt: now) == nil, "reject zero, invalid, or excessive prices")
        }
        require(MathpixCreditEstimate(creditUSD: "1", pendingUSD: "0", observedAt: Date(timeIntervalSinceReferenceDate: .infinity)) == nil, "reject non-finite observation dates")
        let encoded = try JSONEncoder().encode(estimate)
        let decoded = try JSONDecoder().decode(MathpixCreditEstimate.self, from: encoded)
        require(decoded == estimate, "validated decimal strings survive Codable round trip")
        var json = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        json["imagePriceUSD"] = "0"
        do {
            _ = try JSONDecoder().decode(MathpixCreditEstimate.self, from: JSONSerialization.data(withJSONObject: json))
            fatalError("Codable must not bypass validation")
        } catch DecodingError.dataCorrupted {}
        json["imagePriceUSD"] = 0.002
        do {
            _ = try JSONDecoder().decode(MathpixCreditEstimate.self, from: JSONSerialization.data(withJSONObject: json))
            fatalError("JSON numbers must not introduce floating-point currency")
        } catch DecodingError.typeMismatch {}

        // Compare a range of cent-based balances against independent small integers.
        for creditCents in 0...80 {
            for pendingCents in 0...12 {
                for priceMilliDollars in [1, 2, 3, 7] {
                    for count in [0, 1, 4, 5, 6, 16, 101] {
                        let sample = MathpixCreditEstimate(creditUSD: cents(creditCents), pendingUSD: cents(pendingCents), imagePriceUSD: "0.00\(priceMilliDollars)", observedAt: now)!
                        let netMilliDollars = max(0, (creditCents - pendingCents - 1) * 10)
                        let reference = max(0, netMilliDollars / priceMilliDollars - count)
                        require(sample.remainingImages(additionalRequests: count) == reference, "integer cross-check of initial fee reserve and one-for-one local decrements")
                        let knownCostUpperMilliDollars = ((count * priceMilliDollars + 9) / 10) * 10
                        let excessMilliDollars = max(0, knownCostUpperMilliDollars - (pendingCents + 1) * 10)
                        let precisionReference = (excessMilliDollars + priceMilliDollars - 1) / priceMilliDollars
                        require(sample.precisionDebitsForKnownMonthlyImages(count) == precisionReference, "integer cross-check of monthly cost ceiling and precision debit ceiling")
                    }
                }
            }
        }
        print("MathpixCreditEstimateTests passed: exact decimal currency, conservative Billing and known monthly cost reserves, one-for-one local decrements, count floor, exhausted credit, limits, Codable validation and overflow")
    }

    private static func cents(_ value: Int) -> String { "\(value / 100)." + (value % 100 < 10 ? "0" : "") + "\(value % 100)" }
    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
    }
}
