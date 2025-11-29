// @copyright André Trettin

import Foundation
import SwiftUI

public extension EnvironmentValues {
    @Entry var networkActions: NetworkActions? = nil
}

public struct NetworkActions: Sendable {
    public let shareId: @MainActor @Sendable (NetworkCodableDataType) -> Void
    public let send: @MainActor @Sendable (NetworkCodableDataType) -> Void
    public let game: @MainActor @Sendable (NetworkCodableDataType, RPGMessageActionType) -> Void

    public init(shareId: @MainActor @escaping @Sendable (NetworkCodableDataType) -> Void, send: @MainActor @escaping @Sendable (NetworkCodableDataType) -> Void, game: @MainActor @escaping @Sendable (NetworkCodableDataType, RPGMessageActionType) -> Void) {
        self.shareId = shareId
        self.send = send
        self.game = game
    }
    
    @MainActor static let empty = NetworkActions(shareId: { _ in }, send: { _ in }, game: { _, _ in })
}

public struct NetworkCodableDataType: Codable, Sendable {
    public init(id: UUID, type: NetworkModules, version: Int, data: Data? = nil) {
        self.id = id
        self.type = type
        self.version = version
        self.data = data
    }

    public let id: UUID
    public let type: NetworkModules
    public let version: Int
    public let data: Data?

    public static let empty = NetworkCodableDataType(id: UUID(), type: .none, version: 0, data: nil)
}

// MARK: - Mapper

public extension NetworkCodableDataType {
    static func decodeData(of data: Data?) -> NetworkCodableDataType? {
        guard let data else { return nil }
        let decoder = JSONDecoder()
        return try? decoder.decode(NetworkCodableDataType.self, from: data)
    }

    func encodeData() -> Data? {
        let encoder = JSONEncoder()
        return try? encoder.encode(self)
    }
}
