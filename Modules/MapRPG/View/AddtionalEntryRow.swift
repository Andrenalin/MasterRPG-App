// @copyright André Trettin

import CoreRPG
import SwiftUI

struct AddtionalEntryRow: View, Equatable {
    let source: ItemRowModel
    let entry: any EntryDataAccessable
    /// Pre-resolved by the caller where available — see `ViewControllable`'s
    /// doc comment / CODE_AUDIT_10 §8.1. Falls back to `itemOrEmpty` when
    /// nil, so this stays correct for any call site not yet updated.
    var resolvedModel: MapModel? = nil

    @Environment(MapRootModel.self) private var root

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .trailing) {
            HStack {
                Toggle(isOn: $model[entryId].isShown) {
                    Text("Shown", bundle: .module)
                }
                .labelsHidden()

                Text("Shown", bundle: .module)
            }
            Text("\(pinsCounter) pins", bundle: .module)
        }
    }

    private var model: MapModel {
        resolvedModel ?? root.itemController.itemOrEmpty(for: source.itemId)
    }
    
    private var mapEntryModel: MapEntryModel {
        entry as? MapEntryModel ?? model[entryId]
    }
    
    private var entryId: UUID {
        source.entryId ?? UUID()
    }
    
    private var pinsCounter: Int {
        let entryRect = mapEntryModel.rect
        return model.mapPins.filter { entryRect.contains($0.location) }.count
        
    }
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.source == rhs.source
    }
}

#Preview(traits: .mockData) {
    AddtionalEntryRow(
        source: ItemRowModel(
            itemId: MapModel.previewId,
            entryId: MapEntryModel.previewId,
            typeId: .map
        ),
        entry: MapEntryModel.preview
    )
    .environment(MapRootModel.previewFixture())
}
