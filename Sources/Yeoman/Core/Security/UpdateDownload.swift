import Foundation

public final class UpdateDownload: NSObject, URLSessionDataDelegate {
    private let limit: Int
    private let apiRequest: Bool
    private var redirects = 0
    private var data = Data()
    private var continuation: CheckedContinuation<Data, Error>?
    private var failure: Error?
    private var session: URLSession?
    private let configuration: URLSessionConfiguration
    public init(limit: Int, apiRequest: Bool, configuration: URLSessionConfiguration = .ephemeral) {
        self.limit = limit; self.apiRequest = apiRequest; self.configuration = configuration
    }
    public func fetch(_ request: URLRequest) async throws -> Data {
        guard let url = request.url, apiRequest ? url == UpdateURLPolicy.api : UpdateURLPolicy.asset(url) else {
            throw SecurityFailure.rejected("Nicht erlaubte Update-URL.")
        }
        guard limit > 0, continuation == nil, session == nil else {
            throw SecurityFailure.rejected("Downloadinstanz ist bereits in Benutzung.")
        }
        redirects = 0; data = Data(); failure = nil
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            var request = request
            if !apiRequest { request.setValue(nil, forHTTPHeaderField: "Authorization") }
            let config = configuration
            config.httpCookieStorage = nil; config.urlCredentialStorage = nil; config.urlCache = nil
            config.timeoutIntervalForRequest = 20; config.timeoutIntervalForResource = 120
            let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1
            let session = URLSession(configuration: config, delegate: self, delegateQueue: queue)
            self.session = session
            session.dataTask(with: request).resume()
        }
    }
    public func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                           newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        redirects += 1
        guard let url = request.url, UpdateURLPolicy.redirect(url, apiRequest: apiRequest, count: redirects) else {
            failure = SecurityFailure.rejected("Update-Weiterleitung abgewiesen."); completionHandler(nil); task.cancel(); return
        }
        var next = request
        if !apiRequest { next.setValue(nil, forHTTPHeaderField: "Authorization") }
        completionHandler(next)
    }
    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                           completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        let length = response.expectedContentLength
        guard let http = response as? HTTPURLResponse else {
            failure = SecurityFailure.rejected("updates.error_invalid_response")
            completionHandler(.cancel); return
        }
        guard http.statusCode == 200 else {
            if http.statusCode == 404 {
                failure = SecurityFailure.rejected("updates.error_not_found_or_private")
            } else if http.statusCode == 403 {
                failure = SecurityFailure.rejected("updates.error_forbidden")
            } else {
                failure = SecurityFailure.rejected("updates.error_invalid_response")
            }
            completionHandler(.cancel); return
        }
        guard let url = http.url, UpdateURLPolicy.redirect(url, apiRequest: apiRequest, count: redirects),
              length == NSURLSessionTransferSizeUnknown || (length >= 0 && length <= limit) else {
            failure = SecurityFailure.rejected("updates.error_invalid_response"); completionHandler(.cancel); return
        }
        completionHandler(.allow)
    }
    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
        guard chunk.count <= limit - data.count else {
            failure = SecurityFailure.rejected("Update-Download überschreitet Größenlimit."); dataTask.cancel(); return
        }
        data.append(chunk)
    }
    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = failure ?? error { continuation?.resume(throwing: error) }
        else { continuation?.resume(returning: data) }
        continuation = nil; data = Data(); session.finishTasksAndInvalidate(); self.session = nil
    }
}
