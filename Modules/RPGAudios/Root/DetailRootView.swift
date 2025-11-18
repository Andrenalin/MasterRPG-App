// @copyright André Trettin

import AndrenalinKit
import CoreExternalRPG
import SwiftUI

struct DetailRootView: View {
    init(root: AudioRootModel, editController: EditController, model: AudioModel, isSubFolder: Bool) {
        self.root = root
        self.editController = editController
        self.model = model
        self.isSubFolder = isSubFolder
        let listController = root.folderListController.copy(parentModel: model) as! FolderListController
        self._detailFolderListController = State(wrappedValue: listController)
    }
    
    let root: AudioRootModel
    let editController: EditController
    let model: AudioModel
    let isSubFolder: Bool
    
    @Environment(\.navigator) private var navigator
    
    @State private var detailFolderListController: FolderListController
    @State private var openFileWindowModel = OpenFileWindowModel()
    
    var body: some View {
        content(listController: detailFolderListController)
            .onChange(of: detailFolderListController.listModel.subFolderRoute) {
                guard let subItemId = detailFolderListController.listModel.subFolderRoute else { return }
                navigator.navigate(to: AudioDetailRoute.folder(subItemId), method: .push)
                detailFolderListController.listModel.subFolderRoute = nil
            }
    }
    
    func content(listController: any FolderListControllable) -> some View {
        ItemDetailRootView(detailListController: listController, selectedId: model.id, editorAsBackground: false) {
        } editor: {
            fileAndPlayerView(model: model)
        } overlay: {
            playerView
        }
        .toolbar {
            ToolbarItem(placement: .secondaryActionAll) {
                playButton
            }
        }
        .environment(openFileWindowModel)
        .environment(root.folderListController.cacheListItemModel)
        .environment(root.listDisplayModel)
        .environment(root.searchModel)
        .environment(root.rootController)
        .tint(root.module.tint)
        .accentColor(root.module.tint)
    }

    func fileAndPlayerView(model: AudioModel) -> some View {
        HStack {
            HStack {
                FileImporterView(editControllable: editController, fileTypes: editController.fileUrlDataController?.fileTypes ?? [], module: root.module)
                
                Text(model.url?.absoluteString ?? "No file is set")
                    .frame(maxWidth: .infinity, alignment: .leading)
                
            }
            .opacity(model.specialCategory ? 0 : 1)
        }
        .padding()
    }

    var playerView: some View {
#if os(visionOS)
        AudioPlayerBarView()
            .padding()
#else
        GlassEffectContainer {
            AudioPlayerBarView()
                .padding()
        }
#endif
    }
    
    var playButton: some View {
        Button {
            Task {
                let list = root.itemController.audioList(itemId: model.id)
                await root.audioController.add(audio: list, replace: true)
                root.audioController.togglePlay(id: list.first?.id)
            }
        } label: {
            Label {
                Text("Play", bundle: .module)
            } icon: {
                Image(systemName: "play.rectangle.on.rectangle")
            }
        }
        .disabled(!root.itemController.hasAudio(itemId: model.id))
    }
}

#Preview(traits: .mockData) {
    @Previewable @Environment(AudioRootModel.self) var root
    @Previewable @Environment(ListModel.self) var listModel
    
    if listModel.selectedItem == nil {
        Text("Hello")
            .onAppear {
                let id = root.itemController.itemDataModel.items.first ?? AudioModel.previewId
                root.editController(type: .main).model = root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items.first ?? AudioModel.previewId)
                listModel.selectedItem = ItemRowTreeModel(itemId: id, typeId: root.module)
            }
    } else {
        ManagedNavigationStack {
            DetailRootView(root: root, editController: .preview, model: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items.first ?? AudioModel.previewId), isSubFolder: false)
                .preferredColorScheme(.dark)
        }
    }
    
}
