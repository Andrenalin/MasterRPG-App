// @copyright André Trettin

import CoreRPG
import SwiftUI

struct InlineRowViewer: View, Equatable {
    let source: ItemRowModel
    let destination: ItemRowModel
    
    @Environment(DiceRootModel.self) private var root
    @Environment(AppGameStateModel.self) private var appGameStateModel
    
    var body: some View {
        DiceInline(itemId: source.itemId, resultCategory: ResultCategory(source: destination), player: appGameStateModel.gameModus == .player)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.source == rhs.source
    }
}

#Preview(traits: .mockData) {
    InlineRowViewer(source: ItemRowModel(itemId: MockData.previewId, typeId: .dice), destination: ItemRowModel(itemId: UUID(), entryId: nil, typeId: .table))
}
