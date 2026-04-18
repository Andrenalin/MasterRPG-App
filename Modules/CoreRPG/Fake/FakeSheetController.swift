// @copyright André Trettin

import SwiftUI

struct FakeSheetController: SheetControllable {
    func sheet(for itemId: UUID, level: Int) -> SheetModel {
        .empty
    }
    
    @MainActor
    static let fake = FakeSheetController()
}
