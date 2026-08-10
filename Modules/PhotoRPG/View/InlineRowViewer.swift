// @copyright André Trettin

import CoreRPG
import SwiftUI

struct InlineRowViewer: View, Equatable {
    let source: ItemRowModel
    let destination: ItemRowModel
    
    @Environment(PhotoRootModel.self) private var root
    
    @Environment(ScenesManager.self) private var scenesManager
    @Environment(\.navigator) private var navigator
    @Environment(\.appTheme) private var theme

    var body: some View {
        GameShareView(root: root.rootController, itemId: source.itemId) {
            HStack {
                root.viewController.photoRow(root: root, for: source.itemId)
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
