// @copyright André Trettin

import CoreRPG
import SwiftUI

struct InlineRowViewer: View, Equatable {
    let source: ItemRowModel
    let destination: ItemRowModel
    
    @Environment(DiceRootModel.self) private var root
    
    var body: some View {
        DiceInline(itemId: source.itemId, resultCategory: ResultCategory(source: destination))
    }
    
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.source == rhs.source
    }
}

#Preview(traits: .mockData) {
    InlineRowViewer(source: ItemRowModel(itemId: MockData.previewId, typeId: .dice), destination: ItemRowModel(itemId: UUID(), entryId: nil, typeId: .table))
}
