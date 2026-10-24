import Foundation

@main struct MathpixUsageTests {
    static func main() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockProtocol.self]
        let service = MathpixUsageService(appID: "current-app", apiKey: "fake-key-not-in-url",
                                         transport: APITransport(session: URLSession(configuration: configuration)))
        let now = date("2026-12-31T23:59:59Z")
        let request = try service.makeRequest(now: now)
        expect(request.httpMethod == "GET", "usage query is read only")
        expect(request.url?.scheme == "https" && request.url?.host == "api.mathpix.com", "use only the official TLS host")
        expect(request.url?.path == "/v3/ocr-usage", "use the documented usage endpoint")
        expect(request.value(forHTTPHeaderField: "app_id") == "current-app", "App ID uses header authentication")
        expect(request.value(forHTTPHeaderField: "app_key") == "fake-key-not-in-url", "App Key uses header authentication")
        expect(request.url?.absoluteString.contains("fake-key") == false, "the key never enters the URL")
        expect(request.httpBody == nil && request.httpBodyStream == nil, "usage queries never upload an image or body")
        expect(request.timeoutInterval == 15, "usage queries have a bounded timeout")
        let queryItems = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
        let query = Dictionary(grouping: queryItems, by: \.name).mapValues { $0.compactMap(\.value) }
        expect(queryItems.count == 7 && query.count == 6, "only documented query parameters, including repeated grouping, are sent")
        expect(query["from_date"] == ["2026-12-01T00:00:00.000Z"], "UTC month starts inclusively")
        expect(query["to_date"] == ["2027-01-01T00:00:00.000Z"], "UTC next-month end crosses the year exclusively")
        expect(query["group_by"] == ["app_id", "usage_type"], "retain both account and usage type with the official SDK's repeated grouping parameters")
        expect(query["timespan"] == ["month"], "query monthly image usage groups")
        expect(query["app_id"] == nil && query["app_key"] == nil, "authenticate only in headers and filter App ID locally")
        expect(query["page"] == ["1"] && query["per_page"] == ["100"], "make the official SDK's default pagination boundary explicit")

        let response = json(#"{"ocr_usage":[{"app_id":"current-app","usage_type":"image","count":7},{"app_id":"current-app","usage_type":"image-async","count":3},{"app_id":"other-app","usage_type":"image","count":99},{"app_id":"current-app","usage_type":"pdf-pages","count":123},{"app_id":"current-app","usage_type":"strokes","count":42}]}"#)
        let snapshot = try MathpixUsageService.parse(response, appID: "current-app", now: now)
        expect(snapshot.appID == "current-app" && snapshot.imageCount == 10, "sum only this App ID's sync and async images")
        expect(snapshot.periodStart == date("2026-12-01T00:00:00Z"), "snapshot carries the actual requested start")
        expect(snapshot.periodEnd == date("2027-01-01T00:00:00Z"), "snapshot carries the actual requested end")
        expect(snapshot.fetchedAt == now, "snapshot records its query time")
        let empty = try MathpixUsageService.parse(json(#"{"ocr_usage":[]}"#), appID: "current-app", now: now)
        expect(empty.imageCount == 0, "a valid empty response means zero usage")
        let zero = try MathpixUsageService.parse(json(#"{"error":null,"error_info":null,"ocr_usage":[{"app_id":"current-app","usage_type":"image","count":0}]}"#), appID: "current-app", now: now)
        expect(zero.imageCount == 0, "null error fields and a genuine zero are accepted")
        let fullPage = try JSONSerialization.data(withJSONObject: ["ocr_usage": Array(repeating: ["app_id": "current-app", "usage_type": "image", "count": 1] as [String: Any], count: 100)])
        do { _ = try MathpixUsageService.parse(fullPage, appID: "current-app", now: now); fatalError("a full page must not become a potentially truncated monthly count") }
        catch MathpixUsageError.incomplete {}
        catch { fatalError("unexpected incomplete-page error type") }
        let february = try service.makeRequest(now: date("2028-02-29T23:59:59Z"))
        let februaryQuery = URLComponents(url: february.url!, resolvingAgainstBaseURL: false)!.queryItems!
        expect(februaryQuery.first { $0.name == "to_date" }?.value == "2028-03-01T00:00:00.000Z", "leap years use calendar boundaries")

        for body in [
            "not-json", "[]", "{}", #"{"ocr_usage":null}"#, #"{"ocr_usage":{}}"#,
            #"{"ocr_usage":[{}]}"#,
            #"{"ocr_usage":[{"app_id":3,"usage_type":"image","count":1}]}"#,
            #"{"ocr_usage":[{"app_id":null,"usage_type":"image","count":1}]}"#,
            #"{"ocr_usage":[{"usage_type":"image","count":1}]}"#,
            #"{"ocr_usage":[{"app_id":"current-app","usage_type":null,"count":1}]}"#,
            #"{"ocr_usage":[{"app_id":"current-app","usage_type":"image","count":-1}]}"#,
            #"{"ocr_usage":[{"app_id":"current-app","usage_type":"image","count":true}]}"#,
            #"{"ocr_usage":[{"app_id":"current-app","usage_type":"image","count":"7"}]}"#,
            #"{"ocr_usage":[{"app_id":"current-app","usage_type":"image","count":1.5}]}"#,
            #"{"ocr_usage":[{"app_id":"current-app","usage_type":"image","count":9223372036854775808}]}"#,
            #"{"ocr_usage":[{"app_id":"other-app","usage_type":"pdf-pages","count":-1}]}"#,
            #"{"error":true,"ocr_usage":[]}"#,
            #"{"error_info":"raw-server-sensitive","ocr_usage":[]}"#,
            "{\"ocr_usage\":[{\"app_id\":\"current-app\",\"usage_type\":\"image\",\"count\":\(Int.max)},{\"app_id\":\"current-app\",\"usage_type\":\"image-async\",\"count\":1}]}"
        ] {
            assertRejected(json(body), appID: "current-app", now: now)
        }
        for body in [#"{"error":"raw-server-sensitive","ocr_usage":[]}"#,
                     #"{"error_info":{"id":"unknown","message":"raw-server-sensitive"},"ocr_usage":[]}"#] {
            assertRejected(json(body), appID: "current-app", now: now)
        }
        for (id, key) in [("", "key"), ("app", ""), (" \n", "key"), ("app", "  "), ("app\r\ninjected", "key"), ("app", "key\nvalue")] {
            do {
                _ = try MathpixUsageService(appID: id, apiKey: key).makeRequest(now: now)
                fatalError("invalid credentials must be rejected before network use")
            } catch {
                expect(!error.localizedDescription.contains("injected"), "configuration errors never echo values")
            }
        }

        MockProtocol.status = 200; MockProtocol.failNetwork = false; MockProtocol.body = response
        let fetched = try await service.fetch(now: now)
        expect(fetched == snapshot, "fetch returns the validated usage snapshot")
        MockProtocol.body = json(#"{"error":"raw-server-sensitive"}"#)
        for status in [401, 403, 429, 500] {
            MockProtocol.status = status
            do { _ = try await service.fetch(now: now); fatalError("HTTP failures must not become zero usage") }
            catch RecognitionError.http(let actual) { expect(actual == status, "retain only the HTTP status") }
            catch { fatalError("unexpected HTTP error type") }
        }
        MockProtocol.status = 200
        do { _ = try await service.fetch(now: now); fatalError("service errors must be rejected") }
        catch { expect(!error.localizedDescription.contains("raw-server-sensitive"), "service errors never expose response bodies") }
        MockProtocol.failNetwork = true
        do { _ = try await service.fetch(now: now); fatalError("offline usage must remain unavailable") }
        catch RecognitionError.network {}
        catch { fatalError("unexpected network error type") }
        MockProtocol.failNetwork = false
        print("MathpixUsageTests passed: authenticated read-only requests, UTC periods, image filtering, strict counts, overflow, HTTP and network errors")
    }

    private static func date(_ string: String) -> Date { ISO8601DateFormatter().date(from: string)! }

    private static func assertRejected(_ data: Data, appID: String, now: Date) {
        do {
            _ = try MathpixUsageService.parse(data, appID: appID, now: now)
            fatalError("invalid usage responses must remain unavailable, never a fabricated zero")
        } catch {
            expect(!error.localizedDescription.contains("raw-server-sensitive"), "response errors never echo server text")
        }
    }
}
