// @copyright André Trettin

import CoreRPG
import PhotoRPG
import SwiftUI

struct PhotoInlineRow: View, Equatable {
    let itemId: UUID
    
    @Environment(MapRootModel.self) private var root
    
    var body: some View {
        root.photoRoot.viewController.photoRow(root: root.photoRoot, for: itemId)
    }
    
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.itemId == rhs.itemId
    }
}

#Preview(traits: .mockData) {
    PhotoInlineRow(itemId: MockData.previewId)
}
