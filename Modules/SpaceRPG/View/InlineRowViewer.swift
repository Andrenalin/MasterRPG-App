// @copyright André Trettin

import CoreRPG
import SwiftUI

struct InlineRowViewer: View, Equatable {
    let source: ItemRowModel
    let destination: ItemRowModel
    
    @Environment(SpaceRootModel.self) private var root
    
#if !os(tvOS)
    @Environment(\.openWindow) private var openWindow
#endif
    @Environment(\.navigator) private var navigator

    var body: some View {
        if source.typeId == root.config.module {
            ViewerRootView(model: root.itemController.itemOrEmpty(for: source.itemId), configuration: ViewerConfiguration(isGame: false))
                .frame(height: 256)
                .overlay(alignment: .trailing) {
                    Button {
                        actionHandler()
                    } label: {
                        Image(systemName: root.configurable.module.icon)
                            .imageScale(.large)
                    }
                    .padding()
                }
        }
    }
    
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.source == rhs.source
    }
    
    private func actionHandler() {
#if os(visionOS) || os(macOS)
        openWindow(id: root.configurable.module.viewerWindowId, value: WindowItemSelection(itemId: source.itemId, entryId: nil))
#else
        navigator.navigate(to: DetailRoute.viewer(source.itemId), method: .managedSheet)
#endif
    }
}

#Preview(traits: .mockData) {
    InlineRowViewer(source: ItemRowModel(itemId: MockData.previewId, typeId: .space), destination: ItemRowModel(itemId: UUID(), entryId: nil, typeId: .table))
}
