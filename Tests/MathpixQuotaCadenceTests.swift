import Foundation
import Combine

@main struct MathpixQuotaCadenceTests {
    @MainActor
    static func main() async throws {
        let suite = "screenscribe.tests.quota-cadence.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let now = ISO8601DateFormatter().date(from: "2026-10-24T07:30:00Z")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let period = calendar.dateInterval(of: .month, for: now)!
        let configuration = RecognitionConfiguration(backend: .mathpix, model: "", baseURL: "",
                                                     appID: "fake-cadence-app", apiKey: "fake-cadence-key")
        let queries = UsageQueries()
        let usage = MathpixUsageStore(defaults: defaults, now: { now }, fetch: queries.fetch)
        let credit = MathpixCreditStore(defaults: defaults)
        let settings = PhysicsSettings(defaults: defaults,
                                       readCredential: { _ in fatalError("injected credentials must avoid Keychain reads") },
                                       usageStore: usage, creditStore: credit)
        settings.backend = .mathpix
        try settings.rememberCredentials(configuration)
        expect(credit.save(creditUSD: "1.00", pendingUSD: "0.20", observedAt: now), "save a synthetic Billing snapshot covering the baseline image cost")
        expect(credit.setUsageBaseline(imageCount: 100, periodStart: period.start), "establish the synthetic official-use baseline")
        let initial = credit.remainingImages!
        expect(initial == 395, "reserve a conservative cent above the known baseline cost before converting the balance to images")
        expect(queries.count == 0, "saving credentials and a baseline makes no automatic use request")

        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [CadenceProtocol.self]
        let session = URLSession(configuration: sessionConfiguration)
        defer { session.invalidateAndCancel() }
        let provider = MathpixProvider(appID: configuration.appID, apiKey: configuration.apiKey,
                                       transport: APITransport(session: session), beforeSend: {
            await MainActor.run {
                expect(credit.recordAttempt(appID: configuration.appID), "reserve one local image before each send")
            }
        }, afterSend: {
            await settings.completedMathpixRequest(using: configuration)
        })

        for attempt in 1...10 {
            do {
                let result = try await provider.recognize(png: Data([1]), mode: .equation)
                expect(attempt != 3 && attempt != 7 && result.code == "x", "successful mock requests return a formula")
            } catch {
                switch (attempt, error) {
                case (3, RecognitionError.http(500)), (7, RecognitionError.network): break
                default: fatalError("unexpected cadence request result: \(error)")
                }
            }
            expect(CadenceProtocol.state.count == attempt, "each image attempt enters transport exactly once")
            expect(credit.additionalRequests == attempt, "failed requests also reserve one local image")
            expect(credit.remainingImages == initial - attempt, "every request immediately subtracts exactly one image")
            expect(credit.completionRemainder == attempt % 5, "completion cadence follows all actual attempts")

            if attempt < 5 {
                expect(queries.count == 0 && !usage.refreshing, "attempts one through four do not query official use")
                if attempt == 4 {
                    let restored = MathpixCreditStore(defaults: defaults)
                    restored.selectAccount(appID: configuration.appID)
                    expect(restored.completionRemainder == 4 && restored.remainingImages == initial - 4,
                           "restart restores the four completed attempts without restoring their credit")
                }
            } else if attempt == 5 {
                await queries.waitForCount(1)
                expect(usage.refreshing && queries.count == 1, "the fifth completion starts exactly one official-use query")
                queries.complete(imageCount: 102, period: period, now: now)
                await waitForRefresh(usage)
                expect(usage.snapshot?.imageCount == 102, "use the delayed official response as received")
                expect(credit.accountedRequests == 5 && credit.remainingImages == initial - 5,
                       "a stale official count cannot return any locally reserved credit")
            } else if attempt < 10 {
                expect(queries.count == 1 && !usage.refreshing, "attempts six through nine do not query again")
            } else {
                await queries.waitForCount(2)
                expect(usage.refreshing && queries.count == 2, "the tenth completion starts the second official-use query")
                queries.complete(imageCount: 115, period: period, now: now)
                await waitForRefresh(usage)
                expect(usage.snapshot?.imageCount == 115, "the second query can reveal additional consumption")
                expect(credit.accountedRequests == 15 && credit.remainingImages == initial - 15,
                       "official use above the baseline accounts for other consumption without double charging local images")
            }
        }

        expect(queries.count == 2 && credit.additionalRequests == 10 && credit.completionRemainder == 0,
               "ten attempts make exactly two usage queries while keeping ten local reservations")
        expect(queries.configurations.allSatisfy { $0.appID == configuration.appID && $0.apiKey == configuration.apiKey },
               "official-use queries stay in the injected fake credential scope")
        let persisted = String(describing: defaults.persistentDomain(forName: suite) ?? [:])
        expect(!persisted.contains(configuration.appID) && !persisted.contains(configuration.apiKey),
               "account-scoped persistence contains neither the fake App ID nor API Key")
        print("MathpixQuotaCadenceTests passed: per-attempt debits, HTTP/network failures, fifth/tenth completion queries, stale and higher official use, persisted cadence and isolated fake credentials")
    }

    @MainActor
    private static func waitForRefresh(_ usage: MathpixUsageStore) async {
        for await refreshing in usage.$refreshing.values {
            if !refreshing { return }
        }
        fatalError("usage publisher ended before the injected query completed")
    }
}

@MainActor
private final class UsageQueries {
    private(set) var count = 0
    private(set) var configurations: [RecognitionConfiguration] = []
    private var pending: (RecognitionConfiguration, CheckedContinuation<MathpixUsageSnapshot, Error>)?
    private var waiter: (Int, CheckedContinuation<Void, Never>)?

    func fetch(_ configuration: RecognitionConfiguration, _ date: Date) async throws -> MathpixUsageSnapshot {
        try await withCheckedThrowingContinuation { continuation in
            expect(pending == nil, "only one injected usage query may be pending")
            pending = (configuration, continuation)
            count += 1
            configurations.append(configuration)
            if let waiter, count >= waiter.0 {
                self.waiter = nil
                waiter.1.resume()
            }
        }
    }

    func waitForCount(_ target: Int) async {
        guard count < target else { return }
        await withCheckedContinuation { continuation in
            expect(waiter == nil, "one waiter observes the next injected query")
            waiter = (target, continuation)
        }
    }

    func complete(imageCount: Int, period: DateInterval, now: Date) {
        guard let (configuration, continuation) = pending else { fatalError("no injected usage query to complete") }
        pending = nil
        continuation.resume(returning: MathpixUsageSnapshot(appID: configuration.appID, imageCount: imageCount,
                                                           periodStart: period.start, periodEnd: period.end, fetchedAt: now))
    }
}

private final class CadenceProtocol: URLProtocol, @unchecked Sendable {
    final class State: @unchecked Sendable {
        private let lock = NSLock()
        private var requests = 0
        var count: Int {
            lock.lock(); defer { lock.unlock() }
            return requests
        }
        func record() -> Int {
            lock.lock(); defer { lock.unlock() }
            requests += 1
            return requests
        }
    }

    static let state = State()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let attempt = Self.state.record()
        if attempt == 7 {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: attempt == 3 ? 500 : 200,
                                                            httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"latex_styled":"x"}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
