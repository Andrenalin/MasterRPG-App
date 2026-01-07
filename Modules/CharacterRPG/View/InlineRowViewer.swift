// @copyright André Trettin

import CoreRPG
import DiceRPG
import PhotoRPG
import SwiftUI

struct InlineRowViewer: View, Equatable {
    let source: ItemRowModel
    let destination: ItemRowModel
    
    @Environment(CharacterRootModel.self) private var root
    
    var body: some View {
        if source.typeId == .photo {
            root.photoRoot.viewController.photoRow(root: root.photoRoot, for: source.itemId)
        }
        
        if source.typeId == .dice {
            root.diceRoot.viewController.rowViewer(source: source, destination: destination)
                .environment(\.gameModus, .player)
        }
    }
    
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.source == rhs.source
    }
}

#Preview(traits: .mockData) {
    InlineRowViewer(source: ItemRowModel(itemId: MockData.previewId, typeId: .photo), destination: ItemRowModel(itemId: UUID(), entryId: nil, typeId: .table))
}
