// @copyright André Trettin

import CoreRPG
import SwiftUI

struct InlineRowViewer: View, Equatable {
    let source: ItemRowModel
    let destination: ItemRowModel
    
    @Environment(AudioRootModel.self) private var root
    
    var body: some View {
        HStack {
            SharingActionView(itemId: model.id, showPlayControl: true)
        }
    }
    
    var model: AudioModel {
        let item = root.itemController.itemOrEmpty(for: source.itemId)
        guard let entryId = source.entryId else { return item }
        let entry = item[entryId]
        return root.itemController.itemOrEmpty(for: entry.audioId)
    }
    
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.source == rhs.source
    }
}

#Preview(traits: .mockData) {
    InlineRowViewer(source: ItemRowModel(itemId: MockData.previewId, typeId: .pdf), destination: ItemRowModel(itemId: UUID(), entryId: nil, typeId: .table))
}
