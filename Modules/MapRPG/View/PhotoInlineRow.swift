// @copyright André Trettin

import CoreRPG
import PhotoRPG
import SwiftUI

struct InlineRowViewer: View, Equatable {
    let source: ItemRowModel
    
    @Environment(MapRootModel.self) private var root
    
    var body: some View {
        if source.typeId == .photo {
            root.photoRoot.viewController.photoRow(root: root.photoRoot, for: source.itemId)
        }
    }
    
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.source == rhs.source
    }
}

#Preview(traits: .mockData) {
    InlineRowViewer(source: ItemRowModel(itemId: MockData.previewId, typeId: .photo))
}
