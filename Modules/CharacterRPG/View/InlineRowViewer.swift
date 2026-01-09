// @copyright André Trettin

import CoreRPG
import DiceRPG
import PdfRPG
import PhotoRPG
import SwiftUI

struct InlineRowViewer: View, Equatable {
    let source: ItemRowModel
    let destination: ItemRowModel
    
    @Environment(CharacterRootModel.self) private var root
    
    var body: some View {
        let _ = Self._printChanges()
        switch source.typeId {
        case .dice:
            root.diceRoot.viewController.rowViewer(source: source, destination: destination)
                .environment(\.gameModus, .player)
        case .pdf:
            root.pdfRoot.viewController.rowViewer(source: source, destination: destination)
        case .photo:
            root.photoRoot.viewController.photoRow(root: root.photoRoot, for: source.itemId)
        default:
            EmptyView()
        }
    }
    
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.source == rhs.source
    }
}

#Preview(traits: .mockData) {
    InlineRowViewer(source: ItemRowModel(itemId: MockData.previewId, typeId: .photo), destination: ItemRowModel(itemId: UUID(), entryId: nil, typeId: .table))
}
