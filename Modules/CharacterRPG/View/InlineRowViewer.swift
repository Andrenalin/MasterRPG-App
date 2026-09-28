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
    /// Pre-resolved by the caller where available — see `ViewControllable`'s
    /// doc comment / CODE_AUDIT_10 §8.1. Falls back to `itemOrEmpty` when
    /// nil, so this stays correct for any call site not yet updated. Only
    /// covers the `destination.entryId != nil` branch below — the `else`
    /// branch resolves a runtime-remapped `diceSource` id the ancestor
    /// couldn't have known ahead of time.
    var destinationModel: (any ModelType)? = nil

    @Environment(CharacterRootModel.self) private var root
    @Environment(\.isSheetEditor) private var isSheetEditor

    var body: some View {
        switch module {
        case .dice:
            if let entryId = destination.entryId {
                let resolvedModel = (destinationModel as? ValueModel) ?? root.itemController.itemOrEmpty(for: destination.itemId)
                HStack(spacing: 4) {
                    EntryListDiceRow(itemId: destination.itemId, entryId: entryId)
                    if isSheetEditor && resolvedModel[entryId].diceId != nil {
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
        lhs.source == rhs.source && lhs.destination == rhs.destination
    }
}

#Preview(traits: .mockData) {
    InlineRowViewer(source: ItemRowModel(itemId: MockData.previewId, typeId: .photo), destination: ItemRowModel(itemId: UUID(), entryId: nil, typeId: .table))
}
