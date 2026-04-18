// @copyright André Trettin

import Foundation

public protocol SheetControllable: Sendable {
    @MainActor func sheet(for itemId: UUID, level: Int) -> SheetModel
}
