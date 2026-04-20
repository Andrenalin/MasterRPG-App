// @copyright André Trettin

import SwiftUI

struct FakeSheetController: SheetControllable {
    @MainActor func sheet(root: RootManager, itemId: UUID, destination: ItemRowModel?, level: Int) -> SheetModel {
        .empty
    }
    
    @MainActor
    static let fake = FakeSheetController()
}
