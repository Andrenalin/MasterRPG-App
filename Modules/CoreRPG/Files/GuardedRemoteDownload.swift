// @copyright André Trettin

import Foundation

/// Downloads a remote file with a byte cap enforced while the transfer runs and, unless
/// private hosts are allowed, a check of every redirect target. `URLSession.download(from:)`
/// followed redirects to any host (a public URL could bounce the device to a LAN address)
/// and wrote an unbounded body to disk before the size was checked. See CODE_AUDIT_18 §6.4
/// and §6.5.
public enum GuardedRemoteDownload {
    public static func download(from url: URL, maximumBytes: Int, allowsPrivateHosts: Bool = false) async throws -> URL {
        let delegate = Delegate(maximumBytes: maximumBytes, allowsPrivateHosts: allowsPrivateHosts)
        let (temporaryURL, response) = try await URLSession.shared.download(from: url, delegate: delegate)
        if let response = response as? HTTPURLResponse,
           !(200...299).contains(response.statusCode) {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw URLError(.badServerResponse)
        }
        let size = (try? temporaryURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= maximumBytes else {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw URLError(.dataLengthExceedsMaximum)
        }
        return temporaryURL
    }

    private final class Delegate: NSObject, URLSessionDownloadDelegate, Sendable {
        let maximumBytes: Int
        let allowsPrivateHosts: Bool

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
            let isAllowed = allowsPrivateHosts ? target.isSupportedRemoteFileURL : target.isPublicRemoteFileURL
            completionHandler(isAllowed ? request : nil)
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
