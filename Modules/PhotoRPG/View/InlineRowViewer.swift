// @copyright André Trettin

import CoreRPG
import SwiftUI

struct InlineRowViewer: View, Equatable {
    init(source: ItemRowModel, destination: ItemRowModel, sourceModel: (any ModelType)? = nil) {
        self.source = source
        self.destination = destination
        self.sourceModel = sourceModel
    }

    let source: ItemRowModel
    let destination: ItemRowModel
    /// Pre-resolved by the caller where available — see `ViewControllable`'s
    /// doc comment / CODE_AUDIT_10 §8.1. Falls back to `photoRow`'s own
    /// `itemSync` lookup when nil, so this stays correct for any call site
    /// that hasn't been updated to pass it.
    let sourceModel: (any ModelType)?

    @Environment(PhotoRootModel.self) private var root

    @Environment(ScenesManager.self) private var scenesManager
    @Environment(\.navigator) private var navigator
    @Environment(\.appTheme) private var theme

    var body: some View {
        GameShareView(root: root.rootController, itemId: source.itemId) {
            HStack {
                photoContent
                    .background {
                        RoundedRectangle(cornerRadius: 24, style: .continuous).fill(theme.background(for: root.config.module))
                    }
                    .containerShape(.rect(cornerRadius: 24))
                    .background {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(Color.accentColor.tertiary)
                    }
                    .padding(2)
                    .overlay {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(Color.accentColor.secondary, lineWidth: 3)
                    }
                    .padding(1)
                    .frame(maxWidth: .infinity)
            }
            .overlay(alignment: .trailing) {
                Button {
                    actionHandler()
                } label: {
                    Label {
                        Text(title)
                    } icon: {
                        Image(systemName: root.configurable.module.icon)
                    }
                }
                .selectedRoundButton(title: title, module: .photo, isSelected: isPresented)
            }
        }
    }
    
    var title: String {
        String(localized: "Open Photo", bundle: .module)
    }

    @ViewBuilder private var photoContent: some View {
        if let cacheController = root.cacheController {
            if let model = (sourceModel as? PhotoModel) ?? root.itemController.itemSync(for: source.itemId) {
                CachePhotoView(cacheController: cacheController, model: model, highResolution: true)
            }
        }
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.source == rhs.source
    }
    
    var isPresented: Bool {
        scenesManager.getSceneState(for: SceneId(rawValue: root.configurable.module.viewerWindowId)) == .opened
    }
    
    private func actionHandler() {
#if os(visionOS) || os(macOS)
        scenesManager.openWindow(SceneId(rawValue: root.configurable.module.viewerWindowId), selection: WindowItemSelection(itemId: source.itemId, entryId: nil))
#else
        navigator.navigate(to: DetailRoute.viewer(source.itemId), method: .managedSheet)
#endif
    }
}

#Preview(traits: .mockData) {
    VStack {
        InlineRowViewer(source: ItemRowModel(itemId: PhotoModel.previewPaladinId, typeId: .photo), destination: ItemRowModel(itemId: UUID(), entryId: nil, typeId: .table))

        InlineRowViewer(source: ItemRowModel(itemId: PhotoModel.previewRotatedId, typeId: .photo), destination: ItemRowModel(itemId: UUID(), entryId: nil, typeId: .table))

        InlineRowViewer(source: ItemRowModel(itemId: PhotoModel.previewEmptyId, typeId: .photo), destination: ItemRowModel(itemId: UUID(), entryId: nil, typeId: .table))

    }
    .frame(width: 300, height: 600)
}
