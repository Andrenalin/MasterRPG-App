// @copyright André Trettin

import CoreExternalRPG
import CoreRPG
import SwiftData
import SwiftUI

struct AudioRootNewView: View {
    let withoutNavigation: Bool
    
    @Environment(AudioRootModel.self) private var root

    var body: some View {
        let _ = Self._printChanges()
        
        ItemRootView(root: root.rootController, withoutNavigation: withoutNavigation) {
            CoreRPG.DetailRootView {
#if os(visionOS)
                AudioPlayerBarView()
                    .padding()
#else
                GlassEffectContainer {
                    AudioPlayerBarView()
                        .padding()
                }
#endif
            } editor: {
                if let selectedModel {
                    fileAndPlayerView(model: selectedModel)
                }
            }
        }
        .overlay {
            SaveView(root: root)
        }
    }
    
    func fileAndPlayerView(model: ItemDataModel) -> some View {
        HStack {
            HStack {
                FileImporterView(editControllable: root.editControllable, model: model, fileTypes: root.editControllable.fileUrlDataController?.fileTypes ?? [])

                Text(model.url?.absoluteString ?? "No file is set")
                    .frame(maxWidth: .infinity, alignment: .leading)

            }
            .opacity(model.specialCategory ? 0 : 1)

            Button {
                Task {
                    let list = root.newItemController.audioList(itemId: model.id)
                    await root.audioController.add(audio: list, replace: true)
                    root.audioController.togglePlay(id: list.first?.id)
                }
            } label: {
                Image(systemName: "play")
                    .font(.largeTitle)
            }
            .disabled(!root.newItemController.hasAudio(itemId: model.id))
        }
        .padding()
    }

    var selectedModel: ItemDataModel? {
        root.listControllable.listModel.selectedModel
    }

}

struct SaveView: View {
    let root: AudioRootModel
    
    @SceneStorage("AudioNewRoute") private var route: ItemRootRoute?
    @SceneStorage("AudioDisplayModel") private var displayMode: ListDisplayModel.DisplayMode = .medium
    @SceneStorage("AudioListModel") private var listMode: ListDisplayModel.ListMode = .list

    var body: some View {
        let _ = Self._printChanges()

        Color.clear
            .applyItemRootRoute(listControllable: root.listControllable, route: $route)
            .syncListDisplay(listControllable: root.listControllable, displayMode: $displayMode, listMode: $listMode)
    }
}

#Preview("Small", traits: .mockCoreData) {
    ManagedNavigationStack {
        AudioRootNewView(withoutNavigation: true)
    }
}


#Preview("Split", traits: .mockCoreData) {
    AudioRootNewView(withoutNavigation: false)
}
