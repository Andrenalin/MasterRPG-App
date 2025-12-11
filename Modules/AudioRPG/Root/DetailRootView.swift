// @copyright André Trettin

import CoreRPG

import SwiftUI

struct DetailRootView: View {
    let root: AudioRootModel
    let model: AudioModel

    var body: some View {
        DetailListView(root: root, model: model)
            .detailInspectorModifier(folderListControllable: root.folderListController)
    }
}

struct DetailListView: View {
    init(root: AudioRootModel, model: AudioModel) {
        self.root = root
        self.model = model
        let listController = root.folderListController.copy(parentModel: model) as! FolderListController
        self._detailFolderListController = State(wrappedValue: listController)
    }
    
    let root: AudioRootModel
    let model: AudioModel
    
    @Environment(\.navigator) private var navigator
    
    @State private var detailFolderListController: FolderListController
    @State private var openFileWindowModel = OpenFileWindowModel()
    
    var body: some View {
        content(listController: detailFolderListController)
            .onChange(of: detailFolderListController.listModel.subFolderRoute) {
                guard let subItemId = detailFolderListController.listModel.subFolderRoute else { return }
                //resetNavigationStack()
                navigator.navigate(to: AudioDetailRoute.folder(subItemId), method: .push)
                detailFolderListController.listModel.subFolderRoute = nil
            }
    }
    
    func resetNavigationStack() {
        #if os(macOS)
        if navigator.count > 0 {
            let counter = navigator.count
            navigator.popAll()
            print("*** Module: Audio \(counter) --> \(navigator.count)")
        }
        #endif
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
                FileImporterView(editControllable: root.editController, fileTypes: root.editController.fileUrlDataController?.fileTypes ?? [], module: root.module)
                
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
                root.editController.model = root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items.first ?? AudioModel.previewId)
                listModel.selectedItem = ItemRowTreeModel(itemId: id, typeId: root.module)
            }
    } else {
        ManagedNavigationStack {
            DetailRootView(root: root, model: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items.first ?? AudioModel.previewId))
                .preferredColorScheme(.dark)
        }
    }
    
}
