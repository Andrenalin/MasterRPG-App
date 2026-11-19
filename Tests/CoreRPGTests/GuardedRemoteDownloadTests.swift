// @copyright André Trettin

#if canImport(Testing)
import Foundation
import Synchronization
import Testing

@testable import CoreRPG

/// CODE_AUDIT_TestGaps §6.1: the SSRF and size guard of every remote file import. The requests
/// are answered by a `URLProtocol` stub, so a redirect to a LAN host, an oversize body and a
/// non-2xx answer are checked without a network.
@Suite("Guarded remote download")
struct GuardedRemoteDownloadTests {
    // MARK: - Stub

    enum Answer: Sendable {
        case body(Data, status: Int, announcesLength: Bool)
        case redirect(to: URL)
    }

    /// Answers by absolute url, so suites running in parallel do not share state, and records
    /// what was requested.
    final class StubProtocol: URLProtocol, @unchecked Sendable {
        private static let answers = Mutex<[String: Answer]>([:])
        private static let requested = Mutex<[String]>([])

        static func answer(_ answer: Answer, for url: URL) {
            answers.withLock { $0[url.absoluteString] = answer }
        }

        static func wasRequested(_ url: URL) -> Bool {
            requested.withLock { $0.contains(url.absoluteString) }
        }

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            guard let url = request.url else { return }
            Self.requested.withLock { $0.append(url.absoluteString) }
            guard let answer = Self.answers.withLock({ $0[url.absoluteString] }) else {
                client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
                return
            }
            switch answer {
            case .redirect(let target):
                let response = HTTPURLResponse(url: url, statusCode: 302, httpVersion: nil, headerFields: ["Location": target.absoluteString])!
                client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: target), redirectResponse: response)
            case .body(let data, let status, let announcesLength):
                let headers = announcesLength ? ["Content-Length": String(data.count)] : [:]
                let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: headers)!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                // In pieces, so the size check sees the transfer grow.
                var offset = 0
                while offset < data.count {
                    let end = min(offset + 1_024, data.count)
                    client?.urlProtocol(self, didLoad: data[offset..<end])
                    offset = end
                }
                client?.urlProtocolDidFinishLoading(self)
            }
        }

        override func stopLoading() {}
    }

    private static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        return URLSession(configuration: configuration)
    }

    /// A public url that is unique to one test.
    private static func publicUrl(_ path: String = "file") -> URL {
        URL(string: "https://\(UUID().uuidString.lowercased()).example.com/\(path)")!
    }

    private static func download(
        _ url: URL,
        maximumBytes: Int = 10_000,
        allowsPrivateHosts: Bool = false
    ) async throws -> (fileUrl: URL, response: URLResponse) {
        try await GuardedRemoteDownload.downloadWithResponse(
            from: url,
            maximumBytes: maximumBytes,
            allowsPrivateHosts: allowsPrivateHosts,
            session: session()
        )
    }

    // MARK: - Accepted

    @Test("A public file within the limit is downloaded and handed to the caller")
    func happyPath() async throws {
        let url = Self.publicUrl()
        StubProtocol.answer(.body(Data("hello".utf8), status: 200, announcesLength: true), for: url)

        let result = try await Self.download(url)
        defer { try? FileManager.default.removeItem(at: result.fileUrl) }

        #expect(try String(contentsOf: result.fileUrl, encoding: .utf8) == "hello")
        #expect((result.response as? HTTPURLResponse)?.statusCode == 200)
    }

    @Test("A file exactly as big as the limit is accepted")
    func fileAtTheLimit() async throws {
        let url = Self.publicUrl()
        StubProtocol.answer(.body(Data(repeating: 7, count: 3_000), status: 200, announcesLength: true), for: url)

        let result = try await Self.download(url, maximumBytes: 3_000)
        defer { try? FileManager.default.removeItem(at: result.fileUrl) }

        #expect(try Data(contentsOf: result.fileUrl).count == 3_000)
    }

    @Test("A redirect to another public host is followed")
    func publicRedirectIsFollowed() async throws {
        let target = Self.publicUrl("final")
        let url = Self.publicUrl("start")
        StubProtocol.answer(.redirect(to: target), for: url)
        StubProtocol.answer(.body(Data("moved".utf8), status: 200, announcesLength: true), for: target)

        let result = try await Self.download(url)
        defer { try? FileManager.default.removeItem(at: result.fileUrl) }

        #expect(try String(contentsOf: result.fileUrl, encoding: .utf8) == "moved")
    }

    // MARK: - Redirects to private hosts

    @Test("A public url cannot bounce the device to a LAN or loopback address", arguments: [
        "http://192.168.1.5/secret",
        "http://10.0.0.1/secret",
        "http://127.0.0.1/secret",
        "http://localhost/secret",
        "http://printer.local/secret",
        "http://[::1]/secret",
        "http://[::ffff:192.168.1.5]/secret"
    ])
    func redirectToPrivateHostIsRefused(target: String) async throws {
        let privateUrl = try #require(URL(string: target))
        let url = Self.publicUrl()
        StubProtocol.answer(.redirect(to: privateUrl), for: url)
        StubProtocol.answer(.body(Data("private".utf8), status: 200, announcesLength: true), for: privateUrl)

        await #expect(throws: (any Error).self) {
            _ = try await Self.download(url)
        }

        #expect(!StubProtocol.wasRequested(privateUrl), "the private address must never be requested")
    }

    @Test("A caller that allows private hosts may follow a redirect to the LAN")
    func privateRedirectIsFollowedWhenAllowed() async throws {
        let privateUrl = try #require(URL(string: "http://192.168.1.5/\(UUID().uuidString)"))
        let url = Self.publicUrl()
        StubProtocol.answer(.redirect(to: privateUrl), for: url)
        StubProtocol.answer(.body(Data("lan".utf8), status: 200, announcesLength: true), for: privateUrl)

        let result = try await Self.download(url, allowsPrivateHosts: true)
        defer { try? FileManager.default.removeItem(at: result.fileUrl) }

        #expect(try String(contentsOf: result.fileUrl, encoding: .utf8) == "lan")
    }

    @Test("A redirect to a non-web scheme is refused even when private hosts are allowed")
    func fileSchemeRedirectIsRefused() async throws {
        let target = try #require(URL(string: "file:///etc/hosts"))
        let url = Self.publicUrl()
        StubProtocol.answer(.redirect(to: target), for: url)

        await #expect(throws: (any Error).self) {
            _ = try await Self.download(url, allowsPrivateHosts: true)
        }
    }

    // MARK: - Size

    @Test("A body that announces more than the limit is aborted")
    func announcedOversizeIsAborted() async throws {
        let url = Self.publicUrl()
        StubProtocol.answer(.body(Data(repeating: 1, count: 20_000), status: 200, announcesLength: true), for: url)

        await #expect(throws: (any Error).self) {
            _ = try await Self.download(url, maximumBytes: 5_000)
        }
    }

    @Test("A body that does not announce its length is still refused when it is over the limit")
    func unannouncedOversizeIsRefused() async throws {
        let url = Self.publicUrl()
        StubProtocol.answer(.body(Data(repeating: 1, count: 20_000), status: 200, announcesLength: false), for: url)

        await #expect(throws: (any Error).self) {
            _ = try await Self.download(url, maximumBytes: 5_000)
        }
    }

    // MARK: - Status

    @Test("A non-2xx answer is an error and leaves no file behind", arguments: [301, 403, 404, 500])
    func errorStatusIsRefused(status: Int) async throws {
        let url = Self.publicUrl()
        StubProtocol.answer(.body(Data("error page".utf8), status: status, announcesLength: true), for: url)

        await #expect(throws: URLError.self) {
            _ = try await Self.download(url)
        }
    }

    // MARK: - Connected addresses

    @Test("A name that resolved to a private address is detected from the connection")
    func privateConnectedAddress() {
        #expect(GuardedRemoteDownload.containsPrivateAddress(["93.184.216.34", "192.168.0.10"]))
        #expect(GuardedRemoteDownload.containsPrivateAddress(["127.0.0.1"]))
        #expect(GuardedRemoteDownload.containsPrivateAddress(["::1"]))
        #expect(GuardedRemoteDownload.containsPrivateAddress(["fe80::1%en0"]))
        #expect(GuardedRemoteDownload.containsPrivateAddress(["::ffff:10.0.0.1"]))
    }

    @Test("Only public addresses, or none known, are not private")
    func publicConnectedAddress() {
        #expect(!GuardedRemoteDownload.containsPrivateAddress([]))
        #expect(!GuardedRemoteDownload.containsPrivateAddress([nil]))
        #expect(!GuardedRemoteDownload.containsPrivateAddress(["93.184.216.34", nil, "2606:2800:220:1:248:1893:25c8:1946"]))
    }
}
#endif
