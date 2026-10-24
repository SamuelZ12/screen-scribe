import Foundation

private final class RejectRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil) // Never forward credentials to a redirected host.
    }
}

struct APITransport {
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 90
        configuration.timeoutIntervalForResource = 120
        configuration.urlCache = nil
        return URLSession(configuration: configuration, delegate: RejectRedirects(), delegateQueue: nil)
    }()
    var session: URLSession = Self.session

    func send(_ request: URLRequest) async throws -> Data {
        do {
            let (data, response) = try await session.data(for: request)
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse else { throw RecognitionError.malformed }
            guard (200..<300).contains(http.statusCode) else { throw RecognitionError.http(http.statusCode) }
            guard data.count <= 4_000_000 else { throw RecognitionError.malformed }
            return data
        } catch is CancellationError {
            throw RecognitionError.cancelled
        } catch let error as RecognitionError {
            throw error
        } catch let error as URLError where error.code == .cancelled {
            throw RecognitionError.cancelled
        } catch {
            throw RecognitionError.network // Do not expose server bodies, headers or URLs in errors.
        }
    }
}
