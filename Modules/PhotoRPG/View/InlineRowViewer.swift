// @copyright André Trettin

import CoreRPG
import SwiftUI

struct InlineRowViewer: View, Equatable {
    let source: ItemRowModel
    let destination: ItemRowModel
    
    @Environment(PhotoRootModel.self) private var root
    
    @Environment(ScenesManager.self) private var scenesManager
    @Environment(\.navigator) private var navigator

    var body: some View {
        GameShareView(root: root.rootController, itemId: source.itemId) {
            HStack {
                root.viewController.photoRow(root: root, for: source.itemId)
                    .containerShape(.rect(cornerRadius: 24))
                    .background {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(Color.accentColor.tertiary)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(Color.accentColor.secondary, lineWidth: 2)
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
    InlineRowViewer(source: ItemRowModel(itemId: MockData.previewId, typeId: .photo), destination: ItemRowModel(itemId: UUID(), entryId: nil, typeId: .table))
}
