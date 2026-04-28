// @copyright André Trettin

import SwiftUI

struct FakeSheetController: SheetControllable {
    @MainActor func sheet(root: RootManager, itemId: UUID, destination: ItemRowModel?, level: Int, isShown: Bool, moduleDepth: Int) -> SheetModel {
        .empty
    }

    @MainActor func update(root: RootManager, sheetModel: SheetModel) {
        // Fake implementation - no updates needed
    }

    @MainActor
    static let fake = FakeSheetController()
}
