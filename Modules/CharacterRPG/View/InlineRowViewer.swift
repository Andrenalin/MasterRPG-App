// @copyright André Trettin

import CoreRPG
import DiceRPG
import PdfRPG
import PhotoRPG
import SwiftUI
import TableRPG

struct InlineRowViewer: View, Equatable {
    let source: ItemRowModel
    let destination: ItemRowModel
    
    @Environment(CharacterRootModel.self) private var root
    @Environment(\.isSheetEditor) private var isSheetEditor

    var body: some View {
        switch module {
        case .dice:
            if let entryId = destination.entryId {
                HStack(spacing: 4) {
                    EntryListDiceRow(itemId: destination.itemId, entryId: entryId)
                    if isSheetEditor && root.itemController.itemOrEmpty(for: destination.itemId)[entryId].diceId != nil {
                        DiceRowRemoveButton(itemId: destination.itemId, entryId: entryId)
                    }
                }
            } else {
                root.diceRoot.viewController.rowViewer(source: diceSource, destination: destination)
            }
        default:
            EmptyView()
        }
    }
    
    var diceSource: ItemRowModel {
        guard let newDiceId = root.gameController.gameDiceId(itemId: destination.itemId, entryId: destination.entryId ?? UUID()) else {
            return source
        }
        return ItemRowModel(itemId: newDiceId, typeId: .dice)
    }
    
    var module: NetworkModules {
        destination.typeId == .value ? source.typeId : destination.typeId
    }
    
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.source == rhs.source
    }
}

#Preview(traits: .mockData) {
    InlineRowViewer(source: ItemRowModel(itemId: MockData.previewId, typeId: .photo), destination: ItemRowModel(itemId: UUID(), entryId: nil, typeId: .table))
}
