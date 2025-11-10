// @copyright André Trettin

import AndrenalinKit
import CoreExternalRPG
import SwiftUI

struct AudioDetailEditor: View {
    let editController: EditController
    let model: AudioModel
    
    @Environment(AudioRoot.self) private var root

    @State private var openFileWindowModel = OpenFileWindowModel()

    var body: some View {
        ItemDetailRootView(detailListController: root.folderListController.copy(parentModel: selectedModel), selectedId: selectedModel?.id, editorAsBackground: false) {
        } editor: {
            if let model = selectedModel {
                fileAndPlayerView(model: model)
            }
        } inspector: {
            LinkRootView(type: .inspector)
        } overlay: {
            playerView
        }
        .onChange(of: root.folderListController.listModel.selectedItemId, initial: true) {
            update()
        }
        .toolbar {
            ToolbarItem(placement: .secondaryAction) {
                playButton
            }
        }
        .environment(openFileWindowModel)
        .environment(root.folderListController.cacheListItemModel)
        .environment(root.listDisplayModel)
        .environment(root.searchModel)
        .environment(root.rootController)
        .tint(NetworkModules.audio.tint)
        .accentColor(NetworkModules.audio.tint)
    }
    
    var selectedModel: AudioModel? {
        root.folderListController.selectedModel(for: nil) as? AudioModel
    }

    func update() {
        if let item = root.folderListController.listModel.selectedModel as? AudioModel {
            if editController.editorModel.currentItemId != item.id {
                editController.setCurrentItem(to: ItemRowTreeModel(itemId: item.id, typeId: .space))
            }
        } else {
            if editController.editorModel.currentItemId != nil {
                editController.resetCurrentItem(with: "save".localizedString)
            }
        }
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
    @Previewable @Environment(AudioRoot.self) var root
    @Previewable @Environment(ListModel.self) var listModel
    
    if listModel.selectedItem == nil {
        Text("Hello")
            .onAppear {
                let id = root.itemController.itemDataModel.items.first ?? AudioModel.previewId
                root.editController(type: .main).model = root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items.first ?? AudioModel.previewId)
                listModel.selectedItem = ItemRowTreeModel(itemId: id, typeId: .space)
            }
    } else {
        ManagedNavigationStack {
            AudioDetailEditor(editController: .preview, model: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items.first ?? AudioModel.previewId))
                .preferredColorScheme(.dark)
        }
    }
    
}
