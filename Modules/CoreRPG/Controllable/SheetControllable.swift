// @copyright André Trettin

import Foundation

public protocol SheetControllable: Sendable {
    @MainActor func sheet(root: RootManager, itemId: UUID, destination: ItemRowModel?, level: Int) -> SheetModel
}
