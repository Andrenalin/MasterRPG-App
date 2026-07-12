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
        if let data = string.data(using: .utf8), let value = try? JSONDecoder().decode(FileUrl.self, from: data) {
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

    /// Deterministic version derived from the content hash. Unlike `hashValue` it is
    /// stable across processes and devices, so master and player agree on it over the network.
    var contentVersion: Int? {
        guard let contentHash, let digest = Data(base64Encoded: contentHash), digest.count >= 8 else { return nil }
        let value = digest.prefix(8).reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
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
        guard let data = try? JSONEncoder().encode(fileUrl), let text = String(data: data, encoding: .utf8) else { return "" }
        return text
    }

    var rawUrl: URL {
        _url
    }

    var fileExtension: String? {
        _url.pathExtension
    }
}
