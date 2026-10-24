import Foundation

@main struct MathpixProviderTests {
    static func main() async throws {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [MockProtocol.self]
        let provider = MathpixProvider(appID: "test-id", apiKey: "fake-secret", transport: APITransport(session: URLSession(configuration: config)))
        let request = try provider.makeRequest(png: Data([1,2,3]))
        expect(request.url?.query == nil, "key must not appear in URL")
        expect(request.value(forHTTPHeaderField: "app_key") == "fake-secret", "header authentication")
        let payload = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        expect(payload["src"] as? String == "data:image/png;base64,AQID", "only selected pixels")
        expect((payload["data_options"] as? [String: Bool])?["include_latex"] == true, "verified latex format")
        expect(payload["include_line_data"] as? Bool == true, "request line confidence and conversion status")
        expect(payload["include_word_data"] == nil, "live API rejects simultaneous line and word data")
        expect(payload["rm_spaces"] as? Bool == true, "request compact LaTeX token spacing")
        expect(payload["idiomatic_braces"] as? Bool == true, "request equivalent compact single-character scripts")
        expect(payload["idiomatic_eqn_arrays"] as? Bool == false, "preserve returned equation array structure")
        expect(payload["rm_fonts"] == nil, "retain Mathpix default font macro preservation")
        do {
            _ = try MathpixProvider.parse(json(#"{"error":"echoed-secret-must-not-surface","error_info":{"id":"opts_conflict","message":"echoed-secret-must-not-surface"}}"#))
            fatalError("conflicting options accepted")
        } catch {
            expect(error.localizedDescription.contains("opts_conflict"), "show actionable known error ID")
            expect(!error.localizedDescription.contains("echoed-secret"), "never surface raw server errors")
        }
        let emptyError = try MathpixProvider.parse(json(#"{"error":null,"error_info":null,"latex_styled":"x^2+1"}"#))
        expect(emptyError.code == "x^2+1", "null errors are not failures")
        let meaningfulSpacing = #"\text{ a  b }+\mathrm{d}x+\alpha x+\,y\quad z"#
        let preserved = try MathpixProvider.parse(try JSONSerialization.data(withJSONObject: ["latex_styled": meaningfulSpacing]))
        expect(preserved.code == meaningfulSpacing, "local parsing preserves text, font macros, control-word separators and explicit spacing")
        let uncertainLine = try MathpixProvider.parse(json(#"{"latex_styled":"x=y","line_data":[{"text":"x=y","confidence":0.7}]}"#))
        expect(uncertainLine.warnings.contains { $0.contains("待确认行") }, "line-only uncertainty is visible")
        MockProtocol.body = json(#"{"latex_styled":"\\begin{aligned}a&=b\\\\c&=d\\end{aligned}","confidence":0.8,"word_data":[{"text":"l","confidence":0.7}]}"#)
        let result = try await provider.recognize(png: Data([1]), mode: .equation)
        expect(result.confidence == 0.8, "retain real service confidence for the UI")
        expect(result.code.contains("aligned") && result.code.contains("\\\\"), "preserve alignment")
        expect(result.warnings.contains { $0.contains("l") }, "uncertain glyph flagged")
        let fragments = try MathpixProvider.parse(json(#"{"data":[{"type":"latex","value":"a=b"},{"type":"latex","value":"c=d"}]}"#))
        expect(fragments.code.contains("gathered"), "multiple math fragments")
        for invalid in [#"{"text":"Explanation \\(x\\)"}"#, #"{"error":"secret-server-body"}"#, "bad json"] {
            do { _ = try MathpixProvider.parse(json(invalid)); fatalError("must reject invalid response") } catch {}
        }
        for status in [401,403,429,500] {
            MockProtocol.status = status
            do { _ = try await provider.recognize(png: Data([1]), mode: .equation); fatalError("must fail HTTP") }
            catch { expect(!error.localizedDescription.contains("secret"), "redact service errors") }
        }
        MockProtocol.failNetwork = true
        do { _ = try await provider.recognize(png: Data([1]), mode: .equation); fatalError("must fail offline") } catch {}
        do { _ = try provider.makeRequest(png: Data(count: 1_500_001)); fatalError("must reject large base64") } catch {}
        do { _ = try await provider.recognize(png: Data([1]), mode: .feynman); fatalError("Mathpix cannot do TikZ") } catch {}
        let aligned = "\\begin{aligned}a&=b\\\\c&=d\\end{aligned}"
        expect(EquationParser.unwrap("\\[\(aligned)\\]") == aligned, "remove only outer delimiters")
        expect(LatexCopyFormat.inline.wrap("x") == "$x$", "inline copy")
        expect(LatexCopyFormat.display.wrap("x") == "\\[\nx\n\\]", "display copy")
        expect(SnipCopyStyle.display.source("x") == "$$\nx\n$$", "reference-style display copy preserves exact source")
        expect(SnipCopyStyle.equation.source(aligned).contains("\\begin{equation}"), "equation wrapper is valid LaTeX")
        try await testSendCallbacks()
        print("MathpixProviderTests passed: requests, parsing, uncertainty, HTTP/auth/rate limits, network, size, copy formats and reservation/completion/cancellation hooks")
    }

    private static func testSendCallbacks() async throws {
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [ReservationMockProtocol.self]
        let session = URLSession(configuration: sessionConfiguration)
        defer { session.invalidateAndCancel() }
        let transport = APITransport(session: session)

        // Every actual transport attempt completes once, including HTTP, network and parse failures.
        for outcome in [ReservationMockProtocol.Outcome.success, .httpFailure, .networkFailure, .parseFailure] {
            ReservationMockProtocol.state.reset(outcome: outcome)
            let probe = ReservationProbe()
            let provider = MathpixProvider(appID: "test-id", apiKey: "fake-secret", transport: transport, beforeSend: {
                expect(ReservationMockProtocol.state.requestCount == 0, "reserve before sending the request")
                await probe.record()
            }, afterSend: {
                expect(ReservationMockProtocol.state.requestCount == 1, "complete only after transport was entered")
                await probe.complete()
            })
            do {
                let output = try await provider.recognize(png: Data([1]), mode: .equation)
                expect(outcome == .success && output.code == "x", "only a successful request returns output")
            } catch {
                switch (outcome, error) {
                case (.httpFailure, RecognitionError.http(500)), (.networkFailure, RecognitionError.network),
                     (.parseFailure, RecognitionError.malformed): break
                default: fatalError("unexpected pre-send test outcome: \(error)")
                }
            }
            let calls = await probe.count
            let completions = await probe.completions
            let events = await probe.events
            expect(calls == 1, "reserve exactly once for each attempt")
            expect(completions == 1 && events == ["before", "after"], "complete exactly once after reservation for success or failure")
            expect(ReservationMockProtocol.state.requestCount == 1, "each valid attempt is sent once")
        }

        // Local validation errors cannot consume a reservation or start a request.
        let invalidInputs: [(String, String, Data, RecognitionMode)] = [
            ("test-id", "fake-secret", Data([1]), .feynman),
            ("test-id", "fake-secret", Data(), .equation),
            ("test-id", "fake-secret", Data(count: 1_500_001), .equation),
            (" ", "fake-secret", Data([1]), .equation),
            ("test-id", "", Data([1]), .equation),
            ("test\nid", "fake-secret", Data([1]), .equation),
            ("test-id", "fake\nsecret", Data([1]), .equation)
        ]
        for (appID, key, png, mode) in invalidInputs {
            ReservationMockProtocol.state.reset(outcome: .success)
            let probe = ReservationProbe()
            let provider = MathpixProvider(appID: appID, apiKey: key, transport: transport, beforeSend: {
                await probe.record()
            }, afterSend: {
                await probe.complete()
            })
            do { _ = try await provider.recognize(png: png, mode: mode); fatalError("invalid request accepted") }
            catch is RecognitionError {}
            catch { fatalError("invalid input should fail local validation") }
            let calls = await probe.count
            let completions = await probe.completions
            expect(calls == 0, "invalid mode, image or credentials never reserve")
            expect(completions == 0, "invalid requests cannot report a transport completion")
            expect(ReservationMockProtocol.state.requestCount == 0, "invalid requests never reach transport")
        }

        // Cancel deterministically inside a separate task before invoking recognize.
        ReservationMockProtocol.state.reset(outcome: .success)
        let earlyProbe = ReservationProbe()
        let earlyProvider = MathpixProvider(appID: "test-id", apiKey: "fake-secret", transport: transport, beforeSend: {
            await earlyProbe.record()
        }, afterSend: {
            await earlyProbe.complete()
        })
        let earlyCancellation = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await earlyProvider.recognize(png: Data([1]), mode: .equation)
        }
        await expectCancellation(earlyCancellation)
        let earlyCalls = await earlyProbe.count
        let earlyCompletions = await earlyProbe.completions
        expect(earlyCalls == 0, "pre-cancelled requests never reserve")
        expect(earlyCompletions == 0, "pre-cancelled requests never complete a transport attempt")
        expect(ReservationMockProtocol.state.requestCount == 0, "pre-cancelled requests never send")

        // Cancellation during an awaited reservation is checked again before transport.
        ReservationMockProtocol.state.reset(outcome: .success)
        let lateProbe = ReservationProbe()
        let lateProvider = MathpixProvider(appID: "test-id", apiKey: "fake-secret", transport: transport, beforeSend: {
            await lateProbe.record()
            withUnsafeCurrentTask { $0?.cancel() }
        }, afterSend: {
            await lateProbe.complete()
        })
        let lateCancellation = Task { try await lateProvider.recognize(png: Data([1]), mode: .equation) }
        await expectCancellation(lateCancellation)
        let lateCalls = await lateProbe.count
        let lateCompletions = await lateProbe.completions
        expect(lateCalls == 1, "a reservation already made remains conservative after cancellation")
        expect(lateCompletions == 0, "cancellation in the callback cannot complete an unsent request")
        expect(ReservationMockProtocol.state.requestCount == 0, "cancellation in the callback prevents sending")

        // Cancel a task only once its URLProtocol has actually received the request.
        ReservationMockProtocol.state.reset(outcome: .hangUntilCancelled)
        let activeProbe = ReservationProbe()
        let activeProvider = MathpixProvider(appID: "test-id", apiKey: "fake-secret", transport: transport, beforeSend: {
            await activeProbe.record()
        }, afterSend: {
            expect(ReservationMockProtocol.state.requestCount == 1, "transport cancellation still follows one send")
            await activeProbe.complete()
        })
        let activeCancellation = Task { try await activeProvider.recognize(png: Data([1]), mode: .equation) }
        await ReservationMockProtocol.state.waitForRequest()
        activeCancellation.cancel()
        do { _ = try await activeCancellation.value; fatalError("active transport cancellation must fail") }
        catch RecognitionError.cancelled {}
        catch { fatalError("unexpected active transport cancellation error type") }
        let activeCalls = await activeProbe.count
        let activeCompletions = await activeProbe.completions
        let activeEvents = await activeProbe.events
        expect(activeCalls == 1 && activeCompletions == 1 && activeEvents == ["before", "after"],
               "an attempted request completes exactly once even after its task is cancelled")
        expect(ReservationMockProtocol.state.requestCount == 1, "cancelled transport is never retried")
    }

    private static func expectCancellation(_ task: Task<RecognitionOutput, Error>) async {
        do { _ = try await task.value; fatalError("cancelled request must fail") }
        catch is CancellationError {}
        catch { fatalError("unexpected cancellation error type") }
    }
}

private actor ReservationProbe {
    private(set) var count = 0
    private(set) var completions = 0
    private(set) var events: [String] = []
    func record() { count += 1; events.append("before") }
    func complete() { completions += 1; events.append("after") }
}

private final class ReservationMockProtocol: URLProtocol, @unchecked Sendable {
    enum Outcome { case success, httpFailure, networkFailure, parseFailure, hangUntilCancelled }

    final class State: @unchecked Sendable {
        private let lock = NSLock()
        private var outcome = Outcome.success
        private var count = 0
        private var requestStarted: CheckedContinuation<Void, Never>?

        var requestCount: Int {
            lock.lock(); defer { lock.unlock() }
            return count
        }

        func reset(outcome: Outcome) {
            lock.lock(); defer { lock.unlock() }
            self.outcome = outcome
            count = 0
        }

        func recordRequest() -> Outcome {
            lock.lock()
            count += 1
            let continuation = requestStarted
            requestStarted = nil
            let recordedOutcome = outcome
            lock.unlock()
            continuation?.resume()
            return recordedOutcome
        }

        func waitForRequest() async {
            await withCheckedContinuation { continuation in
                lock.lock()
                if count > 0 {
                    lock.unlock()
                    continuation.resume()
                } else {
                    requestStarted = continuation
                    lock.unlock()
                }
            }
        }
    }

    static let state = State()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let outcome = Self.state.recordRequest()
        if outcome == .hangUntilCancelled { return }
        if outcome == .networkFailure {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: outcome == .httpFailure ? 500 : 200,
                                                            httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: outcome == .parseFailure ? Data("invalid JSON".utf8) : Data(#"{"latex_styled":"x"}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
