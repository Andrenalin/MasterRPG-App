// @copyright André Trettin

import CoreRPG
import SwiftUI

struct InlineRowViewer: View, Equatable {
    let source: ItemRowModel
    let destination: ItemRowModel
    
    @Environment(SpaceRootModel.self) private var root
    
    var body: some View {
        if source.typeId == root.config.module {
            ViewerRootView(model: root.itemController.itemOrEmpty(for: source.itemId), configuration: ViewerConfiguration(isGame: false))
                .frame(height: 256)
        }
    }
    
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.source == rhs.source
    }
}

#Preview(traits: .mockData) {
    InlineRowViewer(source: ItemRowModel(itemId: MockData.previewId, typeId: .space), destination: ItemRowModel(itemId: UUID(), entryId: nil, typeId: .table))
}
