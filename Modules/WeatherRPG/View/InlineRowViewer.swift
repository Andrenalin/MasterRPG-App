// @copyright André Trettin

import CoreRPG
import PhotoRPG
import SwiftUI

struct InlineRowViewer: View, Equatable {
    init(source: ItemRowModel, destination: ItemRowModel, sourceModel: (any ModelType)? = nil, useGame: Bool = true, isAnimating: Bool = true) {
        self.source = source
        self.destination = destination
        self.sourceModel = sourceModel
        self.useGame = useGame
        self.isAnimating = isAnimating
    }

    let source: ItemRowModel
    let destination: ItemRowModel
    /// Pre-resolved by the caller where available — see `ViewControllable`'s
    /// doc comment / CODE_AUDIT_10 §8.1. Falls back to `itemOrEmpty` when
    /// nil, so this stays correct for any call site not yet updated.
    let sourceModel: (any ModelType)?
    let useGame: Bool
    let isAnimating: Bool

    @Environment(WeatherRootModel.self) private var root

    @State private var containerSize: CGSize = .zero

    var body: some View {
        Color.clear
            .overlay {
                WeatherViewer(model: (sourceModel as? WeatherModel) ?? root.itemController.itemOrEmpty(for: source.itemId), size: containerSize, useGame: useGame, isAnimating: .constant(isAnimating))
            }
            .onGeometryChange(for: CGSize.self) { proxy in
                proxy.size
            } action: { newValue in
                containerSize = newValue
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
