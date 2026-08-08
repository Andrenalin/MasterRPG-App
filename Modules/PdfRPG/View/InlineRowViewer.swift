// @copyright André Trettin

import CoreRPG
import SwiftUI

struct InlineRowViewer: View, Equatable {
    let source: ItemRowModel
    let destination: ItemRowModel
    
    @Environment(PdfRootModel.self) private var root
    
    @Environment(ScenesManager.self) private var scenesManager
    @Environment(\.navigator) private var navigator


    var body: some View {
        if let cacheController = root.cacheController {
            HStack {
                if source.entryId == nil {
                    ThumbnailRowPhotoView(cacheController: cacheController, model: model, listDisplayModel: root.folderListController.listDisplayModel, entryId: source.entryId)
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
                Button {
                    actionHandler()
                } label: {
                    Label {
                        Text(title)
                    } icon: {
                        Image(systemName: root.configurable.module.icon)
                    }
                }
                .selectedRoundButton(title: title, module: .pdf, isSelected: isPresented)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    var model: PdfModel {
        root.itemController.itemOrEmpty(for: source.itemId)
    }

    var title: String {
        String(localized: "Open PDF", bundle: .module)
    }

    var isPresented: Bool {
        scenesManager.getSceneState(for: SceneId(rawValue: root.configurable.module.viewerWindowId)) == .opened
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.source == rhs.source
    }
    
    private func actionHandler() {
#if os(visionOS) || os(macOS)
        scenesManager.openWindow(SceneId(rawValue: root.configurable.module.viewerWindowId), selection: WindowItemSelection(itemId: destination.itemId, entryId: destination.entryId))
#else
        navigator.navigate(to: DetailRoute.viewer(destination.itemId, destination.entryId), method: .managedSheet)
#endif
    }
}

#Preview(traits: .mockData) {
    InlineRowViewer(source: ItemRowModel(itemId: MockData.previewId, typeId: .pdf), destination: ItemRowModel(itemId: UUID(), entryId: nil, typeId: .table))
}
