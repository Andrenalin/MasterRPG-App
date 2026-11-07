// @copyright André Trettin

import CoreRPG
import SwiftUI

struct InlineRowViewer: View, Equatable {
    let source: ItemRowModel
    /// Pre-resolved by the caller where available — see `ViewControllable`'s
    /// doc comment / CODE_AUDIT_10 §8.1. Only covers the `source.entryId ==
    /// nil` case below directly; the entry-linked case still needs its own
    /// lookup since `entry.audioId` is only known once `item` itself is
    /// resolved.
    var sourceModel: (any ModelType)? = nil

    @Environment(AudioRootModel.self) private var root

    var body: some View {
        HStack {
            SharingActionView(itemId: model.id, showPlayControl: true)
        }
    }

    var model: AudioModel {
        let item = (sourceModel as? AudioModel) ?? root.itemController.itemOrEmpty(for: source.itemId)
        guard let entryId = source.entryId else { return item }
        let entry = item[entryId]
        return root.itemController.itemOrEmpty(for: entry.audioId)
    }
    
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.source == rhs.source
    }
}

#Preview(traits: .mockData) {
    InlineRowViewer(source: ItemRowModel(itemId: MockData.previewId, typeId: .pdf))
}
