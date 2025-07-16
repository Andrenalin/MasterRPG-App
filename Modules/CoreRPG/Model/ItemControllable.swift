// @copyright André Trettin

import Foundation

public protocol ItemControllable: Sendable  {
    associatedtype Model: ItemDataAccessable & Codable
    
    func allItemIds() -> [UUID]
    func item(for: UUID) async -> Model?
    func itemSync(for: UUID) -> Model?
    func fileUrl(for: UUID) async -> FileUrl?
}
