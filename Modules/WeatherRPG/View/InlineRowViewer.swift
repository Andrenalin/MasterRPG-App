// @copyright André Trettin

import CoreRPG
import PhotoRPG
import SwiftUI

struct InlineRowViewer: View, Equatable {
    init(source: ItemRowModel, destination: ItemRowModel, useGame: Bool = true, isAnimating: Bool = true) {
        self.source = source
        self.destination = destination
        self.useGame = useGame
        self.isAnimating = isAnimating
    }

    let source: ItemRowModel
    let destination: ItemRowModel
    let useGame: Bool
    let isAnimating: Bool
    
    @Environment(WeatherRootModel.self) private var root
    
    var body: some View {
        GeometryReader { proxy in
            WeatherViewer(model: root.itemController.itemOrEmpty(for: source.itemId), size: proxy.size, useGame: useGame, isAnimating: .constant(isAnimating))
        }
        .frame(height: 256)
        .clipped()
    }
    
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.source == rhs.source
    }
}

#Preview(traits: .mockData) {
    InlineRowViewer(
        source: ItemRowModel(itemId: MockData.previewId, typeId: .weather),
        destination: ItemRowModel(itemId: .fixture2, entryId: nil, typeId: .table),
        useGame: false,
        isAnimating: false
    )
}
