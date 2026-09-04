// @copyright André Trettin

import CoreRPG
import SwiftUI

struct InlineRowViewer: View, Equatable {
    let source: ItemRowModel
    let destination: ItemRowModel
    /// Pre-resolved by the caller where available — see `ViewControllable`'s
    /// doc comment / CODE_AUDIT_10 §8.1. Falls back to `itemOrEmpty` when
    /// nil, so this stays correct for any call site not yet updated.
    var sourceModel: (any ModelType)? = nil

    @Environment(SpaceRootModel.self) private var root

    @Environment(ScenesManager.self) private var scenesManager
    @Environment(\.navigator) private var navigator

    var body: some View {
        ViewerRootView(model: (sourceModel as? SpaceModel) ?? root.itemController.itemOrEmpty(for: source.itemId), configuration: ViewerConfiguration(isGame: false))
            .frame(height: 256)
            .overlay(alignment: .trailing) {
                Button {
                    actionHandler()
                } label: {
                    Label {
                        Text("Open 3D Object", bundle: .module)
                    } icon: {
                        Image(systemName: root.configurable.module.icon)
                    }
                    .labelStyle(.iconOnly)
                    .imageScale(.large)
                }
                .frame(minWidth: 44, minHeight: 44)
                .padding()
            }
    }
    
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.source == rhs.source
    }
    
    private func actionHandler() {
#if os(visionOS)
        // No 2D window for 3D objects on visionOS — open the ImmersiveSpace instead.
        Task { await scenesManager.openSpaceViewer(selection: ItemSelection(itemId: source.itemId, entryId: nil)) }
#elseif os(macOS)
        scenesManager.openWindow(SceneId(rawValue: root.configurable.module.viewerWindowId), selection: WindowItemSelection(itemId: source.itemId, entryId: nil))
#else
        navigator.navigate(to: DetailRoute.viewer(source.itemId), method: .managedSheet)
#endif
    }
}

#Preview(traits: .mockData) {
    InlineRowViewer(source: ItemRowModel(itemId: MockData.previewId, typeId: .space), destination: ItemRowModel(itemId: UUID(), entryId: nil, typeId: .table))
}
