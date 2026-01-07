// @copyright André Trettin

import CoreRPG
import PhotoRPG
import SwiftUI

struct InlineRowViewer: View, Equatable {
    let source: ItemRowModel
    let destination: ItemRowModel
    
    @Environment(WeatherRootModel.self) private var root
    
    var body: some View {
        if source.typeId == root.config.module {
            GeometryReader { proxy in
                WeatherViewer(model: root.itemController.itemOrEmpty(for: source.itemId), size: proxy.size, useGame: true, isAnimating: .constant(true))
            }
            .frame(height: 256)
        }
    }
    
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.source == rhs.source
    }
}

#Preview(traits: .mockData) {
    InlineRowViewer(source: ItemRowModel(itemId: MockData.previewId, typeId: .weather), destination: ItemRowModel(itemId: UUID(), entryId: nil, typeId: .table))
}
