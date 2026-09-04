// @copyright André Trettin

import CoreRPG
import DiceRPG
import PdfRPG
import PhotoRPG
import SwiftUI
import AudioRPG
import TableRPG
import CharacterRPG

struct InlineRowViewer: View, Equatable {
    let source: ItemRowModel
    let destination: ItemRowModel
    /// Pre-resolved by the caller where available — see `ViewControllable`'s
    /// doc comment / CODE_AUDIT_10 §8.1. Falls back to `itemOrEmpty` when
    /// nil, so this stays correct for any call site not yet updated.
    var sourceModel: (any ModelType)? = nil

    @Environment(MapRootModel.self) private var root

    var body: some View {
        if let cacheController = root.cacheController {
            GameShareView(root: root.rootController, itemId: model.id) {
                HStack {
                    VStack {
                        ThumbnailRowPhotoView(cacheController: cacheController, model: model, listDisplayModel: root.listDisplayModel, entryId: source.entryId)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    AddtionalEntryRow(source: source, entry: entry, resolvedModel: model)
                }
            }
        }
    }

    var module: NetworkModules {
        destination.typeId == .map ? source.typeId : destination.typeId
    }

    var model: MapModel {
        (sourceModel as? MapModel) ?? root.itemController.itemOrEmpty(for: source.itemId)
    }
    
    var entry: MapEntryModel {
        model[source.entryId ?? UUID()]
    }
    
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.source == rhs.source
    }
}

#Preview(traits: .mockData) {
    InlineRowViewer(source: ItemRowModel(itemId: MockData.previewId, typeId: .photo), destination: ItemRowModel(itemId: UUID(), entryId: nil, typeId: .table))
}
