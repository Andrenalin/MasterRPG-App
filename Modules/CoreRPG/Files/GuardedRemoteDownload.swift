// @copyright André Trettin

import Foundation
import Synchronization

/// Downloads a remote file with a byte cap enforced while the transfer runs and, unless
/// private hosts are allowed, a check of every redirect target. `URLSession.download(from:)`
/// followed redirects to any host (a public URL could bounce the device to a LAN address)
/// and wrote an unbounded body to disk before the size was checked. See CODE_AUDIT_18 §6.4
/// and §6.5.
public enum GuardedRemoteDownload {
    public static func download(from url: URL, maximumBytes: Int, allowsPrivateHosts: Bool = false) async throws -> URL {
        try await downloadWithResponse(from: url, maximumBytes: maximumBytes, allowsPrivateHosts: allowsPrivateHosts).fileUrl
    }

    /// `download(from:maximumBytes:allowsPrivateHosts:)` that also returns the response, for
    /// callers that check its MIME type. See CODE_AUDIT_19 §6.2.
    public static func downloadWithResponse(
        from url: URL,
        maximumBytes: Int,
        allowsPrivateHosts: Bool = false
    ) async throws -> (fileUrl: URL, response: URLResponse) {
        try await downloadWithResponse(from: url, maximumBytes: maximumBytes, allowsPrivateHosts: allowsPrivateHosts, session: Self.session)
    }

    /// The download on `session`. A test passes a session whose configuration carries a
    /// `URLProtocol` stub, so the guards run without a network. See CODE_AUDIT_TestGaps §6.1.
    static func downloadWithResponse(
        from url: URL,
        maximumBytes: Int,
        allowsPrivateHosts: Bool,
        session: URLSession
    ) async throws -> (fileUrl: URL, response: URLResponse) {
        let delegate = Delegate(maximumBytes: maximumBytes, allowsPrivateHosts: allowsPrivateHosts)
        let (temporaryUrl, response) = try await session.download(from: url, delegate: delegate)
        // A host name can resolve to a loopback or LAN address, and so can any redirect hop,
        // which the string check cannot see. The addresses actually connected to are checked
        // after the transfer; a private one discards the file. See CODE_AUDIT_20 §6.2.
        if delegate.connectedToPrivateAddress {
            try? FileManager.default.removeItem(at: temporaryUrl)
            throw URLError(.cannotConnectToHost)
        }
        if let response = response as? HTTPURLResponse,
           !(200...299).contains(response.statusCode) {
            try? FileManager.default.removeItem(at: temporaryUrl)
            throw URLError(.badServerResponse)
        }
        let size = (try? temporaryUrl.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= maximumBytes else {
            try? FileManager.default.removeItem(at: temporaryUrl)
            throw URLError(.dataLengthExceedsMaximum)
        }
        return (temporaryUrl, response)
    }

    /// Whether any address a transfer connected to (its own and every redirect hop's) is not a
    /// public one. An unknown address (`nil`) is not counted.
    static func containsPrivateAddress(_ remoteAddresses: [String?]) -> Bool {
        remoteAddresses.contains { address in
            guard let address else { return false }
            return !URL.isPublicAddressLiteral(address)
        }
    }

    /// `URLSession.shared` gives a transfer seven days to finish, so a host that drips bytes
    /// would hold its cache file for that long. See CODE_AUDIT_23 §3.2.
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForResource = 300
        return URLSession(configuration: configuration)
    }()

    private final class Delegate: NSObject, URLSessionDownloadDelegate, Sendable {
        let maximumBytes: Int
        let allowsPrivateHosts: Bool
        private let sawPrivateAddress = Mutex(false)

        var connectedToPrivateAddress: Bool {
            sawPrivateAddress.withLock { $0 }
        }

        init(maximumBytes: Int, allowsPrivateHosts: Bool) {
            self.maximumBytes = maximumBytes
            self.allowsPrivateHosts = allowsPrivateHosts
        }

        // The completion-handler form on purpose: the async form of this `@objc` delegate
        // method crashes the Swift 6.4 compiler (SILGen, native-to-foreign thunk).
        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest,
            completionHandler: @escaping @Sendable (URLRequest?) -> Void
        ) {
            guard let target = request.url else {
                completionHandler(nil)
                return
            }
            let isAllowed = allowsPrivateHosts ? target.isSupportedRemoteFileUrl : target.isPublicRemoteFileUrl
            completionHandler(isAllowed ? request : nil)
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
            guard !allowsPrivateHosts else { return }
            if GuardedRemoteDownload.containsPrivateAddress(metrics.transactionMetrics.map(\.remoteAddress)) {
                sawPrivateAddress.withLock { $0 = true }
            }
        }

        func urlSession(
            _ session: URLSession,
            downloadTask: URLSessionDownloadTask,
            didWriteData bytesWritten: Int64,
            totalBytesWritten: Int64,
            totalBytesExpectedToWrite: Int64
        ) {
            if totalBytesWritten > Int64(maximumBytes) || totalBytesExpectedToWrite > Int64(maximumBytes) {
                downloadTask.cancel()
            }
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
            // The async `download(from:delegate:)` API hands the file to its caller.
        }
    }
}
