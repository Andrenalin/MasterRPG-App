// @copyright André Trettin

import CryptoKit
import Foundation

public struct FileUrl: Equatable, Hashable, Codable, Sendable {
    public let fileId: UUID
    private var _url: URL
    public let location: FileLocation
    public let module: String
    public private(set) var data: Data?
    /// SHA256 of the file's binary data (base64). Stable across storage locations and
    /// devices — the same binary always produces the same hash, unlike the url or the
    /// CRDT update UUID. Nil for legacy items whose data was never seen on this device.
    public private(set) var contentHash: String?

    public init(fileId: UUID, url: URL, location: FileLocation?, module: String, relativeUrl: URL?, contentHash: String? = nil) {
        self.fileId = fileId
        self._url = relativeUrl ?? url
        self.location = location ?? .other
        self.module = module
        self.contentHash = contentHash
    }

    public init?(string: String, fileId: UUID? = nil, module: String? = nil, unconvertedData: Data? = nil) {
        if let data = string.data(using: .utf8), let value = try? JSONCoding.decoder.decode(FileUrl.self, from: data) {
            self.fileId = value.fileId
            self._url = value._url
            self.location = value.location
            self.module = value.module
            self.data = unconvertedData
            self.contentHash = value.contentHash ?? unconvertedData.map(Self.contentHash(of:))
        } else if let unconvertedData {
            self.fileId = fileId ?? UUID()
            self._url = URL(filePath: "")
            self.location = .appCloud
            self.module = module ?? "ERROR"
            self.data = unconvertedData
            self.contentHash = Self.contentHash(of: unconvertedData)
        } else {
            return nil
        }
    }

    /// Creates the transient file descriptor used by staged external imports.
    /// No file is written until `FileUrlDataController.createNewFileUrl` receives
    /// this value during the commit phase.
    public init(importedData data: Data, fileId: UUID, filename: String, module: String) {
        let basename = URL(filePath: filename).lastPathComponent
        let safeBasename = basename.isEmpty ? "attachment" : basename
        let encodedBasename = safeBasename.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "attachment"
        self.fileId = fileId
        self._url = URL(string: encodedBasename) ?? URL(filePath: "attachment")
        self.location = .newCloud
        self.module = module
        self.data = data
        self.contentHash = Self.contentHash(of: data)
    }
}

public extension FileUrl {
    // `data` is a transient transport field — exclude it from equality and hashing
    // so that storing a file locally (which attaches/detaches data) does not change
    // the CRDT update UUID and therefore does not change the item version.
    // `contentHash` is included: same url with different binary data is a change.
    static func == (lhs: FileUrl, rhs: FileUrl) -> Bool {
        lhs.fileId == rhs.fileId &&
        lhs.rawUrl == rhs.rawUrl &&
        lhs.location == rhs.location &&
        lhs.module == rhs.module &&
        lhs.contentHash == rhs.contentHash
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(fileId)
        hasher.combine(rawUrl)
        hasher.combine(location)
        hasher.combine(module)
        hasher.combine(contentHash)
    }

    static func contentHash(of data: Data) -> String {
        Data(SHA256.hash(data: data)).base64EncodedString()
    }

    /// Byte length taken from the SHA256 content-hash digest to derive `contentVersion`
    /// (one `UInt64`) and, separately, `SingleReviewFilePropertyRow.reviewThumbnailKey`
    /// (one `UUID`). Named so both sites can't silently drift if the hash algorithm's
    /// output length ever changes. See CODE_AUDIT.md §9.5.
    static let versionDigestByteCount = 8

    /// Deterministic version derived from the content hash. Unlike `hashValue` it is
    /// stable across processes and devices, so master and player agree on it over the network.
    var contentVersion: Int? {
        guard let contentHash, let digest = Data(base64Encoded: contentHash), digest.count >= Self.versionDigestByteCount else { return nil }
        let value = digest.prefix(Self.versionDigestByteCount).reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
        return Int(bitPattern: UInt(truncatingIfNeeded: value))
    }

    /// Deterministic version derived from a CRDT update UUID — the fallback for
    /// items whose content hash is unknown. Stable across processes and devices,
    /// unlike `UUID.hashValue`, which is randomly seeded per launch and forced a
    /// full re-transfer on every reveal.
    static func versionValue(of update: UUID) -> Int {
        let bytes = update.uuid
        let high = [bytes.0, bytes.1, bytes.2, bytes.3, bytes.4, bytes.5, bytes.6, bytes.7]
            .reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
        let low = [bytes.8, bytes.9, bytes.10, bytes.11, bytes.12, bytes.13, bytes.14, bytes.15]
            .reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
        return Int(bitPattern: UInt(truncatingIfNeeded: high ^ low))
    }

    mutating func resetData(_ data: Data) {
        self.data = data
        self.contentHash = Self.contentHash(of: data)
    }

    /// Calculates the content hash without attaching the data, e.g. when backfilling
    /// the hash for a legacy item whose file is already on disk.
    mutating func resetContentHash(of data: Data) {
        self.contentHash = Self.contentHash(of: data)
    }

    mutating func convertFile(_ data: Data, fileExtension: String) {
        self.data = data
        self.contentHash = Self.contentHash(of: data)
        _url = _url.deletingPathExtension().appendingPathExtension(fileExtension)
    }
    
    var hasUnconvertedData: Bool {
        data != nil
    }

    var rawValue: String {
        var fileUrl = self
        fileUrl.data = nil
        guard let data = try? JSONCoding.encoder.encode(fileUrl), let text = String(data: data, encoding: .utf8) else { return "" }
        return text
    }

    var rawUrl: URL {
        _url
    }

    var fileExtension: String? {
        _url.pathExtension
    }

    var isRemoteURL: Bool {
        location == .url && rawUrl.isSupportedRemoteFileURL
    }

    /// A copy that is safe to resolve on this device although its description came from an
    /// imported file or a game peer, which control every field of it.
    ///
    /// - Cloud/local locations keep their url unless it contains `.`/`..` segments, which are
    ///   removed (unchanged urls stay byte-identical so item versions do not change).
    /// - `.other` (a picked file on the *sender's* device) and `.url` values that are not a
    ///   public http(s) address cannot be resolved here, so they become an app-owned
    ///   `.newCloud` file named after the last path component only.
    ///
    /// See CODE_AUDIT_15 §5.1 and §6.3.
    func sanitizedForImport(allowsPrivateRemoteHosts: Bool = false) -> FileUrl {
        switch location {
        case .url:
            let isAllowed = allowsPrivateRemoteHosts ? rawUrl.isSupportedRemoteFileURL : rawUrl.isPublicRemoteFileURL
            return isAllowed ? self : relocatedToAppStorage()
        case .other:
            return relocatedToAppStorage()
        case .appCloud, .icloud, .local, .newCloud:
            guard CloudDocumentController.hasTraversalComponents(_url) else { return self }
            var copy = self
            copy._url = Self.relativeUrl(fromComponents: CloudDocumentController.safeComponents(_url.pathComponents))
            return copy
        }
    }

    private func relocatedToAppStorage() -> FileUrl {
        let name = CloudDocumentController.safeComponents(_url.pathComponents).last ?? "attachment"
        var result = FileUrl(
            fileId: fileId,
            url: Self.relativeUrl(fromComponents: [name]),
            location: .newCloud,
            module: module,
            relativeUrl: nil,
            contentHash: contentHash
        )
        result.data = data
        return result
    }

    private static func relativeUrl(fromComponents components: [String]) -> URL {
        var url = URL(string: "/") ?? URL(filePath: "/")
        components.forEach { url.append(path: $0) }
        return url
    }
}

public extension URL {
    /// An http(s) url whose host is not this device or a private network. Peers can send
    /// `FileUrl`s that make the receiving device fetch them, so loopback, link-local and
    /// private-range hosts (probing the GM's LAN) are refused. See CODE_AUDIT_15 §6.3.
    var isPublicRemoteFileURL: Bool {
        guard isSupportedRemoteFileURL, var host = host()?.lowercased() else { return false }
        // A trailing "." is a legal DNS root label — "localhost." resolves identically to
        // "localhost" but previously missed every suffix/equality check below. See
        // CODE_AUDIT_17 §6.10.
        if host.hasSuffix(".") { host.removeLast() }
        if host == "localhost" || host.hasSuffix(".localhost") || host.hasSuffix(".local")
            || host.hasSuffix(".internal") || host.hasSuffix(".lan") || !host.contains(".") && !host.contains(":") {
            return false
        }
        if host.contains(":") {
            // IPv6 literal: loopback, unspecified, unique-local, link-local, v4-mapped.
            let value = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            return !(value == "::1" || value == "::" || value.hasPrefix("fc") || value.hasPrefix("fd")
                || value.hasPrefix("fe8") || value.hasPrefix("fe9") || value.hasPrefix("fea")
                || value.hasPrefix("feb") || value.hasPrefix("::ffff:"))
        }
        let octets = host.split(separator: ".").compactMap { Int($0) }
        if octets.count == 4, octets.count == host.split(separator: ".").count {
            switch (octets[0], octets[1]) {
            case (0, _), (10, _), (127, _), (169, 254), (192, 168): return false
            case (172, 16...31), (100, 64...127): return false
            default: return true
            }
        }
        // Not a clean 4-octet dotted-quad. A host whose every label is a numeric IPv4 part
        // (decimal/octal digits, or `0x`-prefixed hex — e.g. "127.1", "0x7f.0.0.1", a bare
        // decimal like "2130706433") is a shorthand IPv4 literal `getaddrinfo` still
        // resolves, not a real DNS name — refuse it (CODE_AUDIT_17 §6.10). Labels made of
        // hex *letters* without the `0x` prefix (e.g. "cafe.be") are real hostnames and are
        // allowed. See CODE_AUDIT_18 §6.5.
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        let looksLikeNumericIPLiteral = !labels.isEmpty && labels.allSatisfy { label in
            if label.hasPrefix("0x") {
                return label.dropFirst(2).allSatisfy(\.isHexDigit)
            }
            return !label.isEmpty && label.allSatisfy { $0.isASCII && $0.isNumber }
        }
        return !looksLikeNumericIPLiteral
    }

    var isSupportedRemoteFileURL: Bool {
        guard let scheme = scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              host() != nil else {
            return false
        }
        return true
    }
}
