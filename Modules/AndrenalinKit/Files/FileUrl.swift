// @copyright André Trettin

import Foundation

public struct FileUrl: Equatable, Hashable, Codable, Sendable {
    public let fileId: UUID
    private var _url: URL
    public let location: FileLocation
    public let module: String
    public private(set) var data: Data?

    public init(fileId: UUID, url: URL, location: FileLocation?, module: String, relativeUrl: URL?) {
        self.fileId = fileId
        self._url = relativeUrl ?? url
        self.location = location ?? .other
        self.module = module
    }

    public init?(string: String, fileId: UUID? = nil, module: String? = nil, unconvertedData: Data? = nil) {
        if let data = string.data(using: .utf8), let value = try? JSONDecoder().decode(FileUrl.self, from: data) {
            self.fileId = value.fileId
            self._url = value._url
            self.location = value.location
            self.module = value.module
            self.data = unconvertedData
        } else if let unconvertedData {
            self.fileId = fileId ?? UUID()
            self._url = URL(filePath: "")
            self.location = .appCloud
            self.module = module ?? "ERROR"
            self.data = unconvertedData
        } else {
            return nil
        }
    }
}

public extension FileUrl {
    mutating func resetData(_ data: Data) {
        self.data = data
    }
    
    mutating func convertFile(_ data: Data, fileExtension: String) {
        self.data = data
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
