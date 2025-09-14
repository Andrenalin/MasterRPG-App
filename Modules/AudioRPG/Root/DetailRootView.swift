// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI

struct DetailRootView: View {
    let selectedId: UUID?
    
    @Environment(\.modelContext) private var modelContext
    @Environment(AudioRootModel.self) private var root
    
    @State private var openFileWindowModel = OpenFileWindowModel()

    var body: some View {
        ItemDetailRootView(selectedId: selectedId) {
        } editor: {
            Group {
                if let selectedModel {
                    ItemDetailOverlayView(model: selectedModel, onlyDescription: true)
                    
                    fileAndPlayerView(model: selectedModel)
                }
            }
        } overlay: {
            playerView
        }
        .environment(openFileWindowModel)
    }
}

private extension DetailRootView {
    var selectedModel: ItemDataModel? {
        root.listControllable.selectedModel(for: selectedId, modelContext: modelContext)
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
                    let list = root.itemController.audioList(itemId: model.id)
                    await root.audioController.add(audio: list, replace: true)
                    root.audioController.togglePlay(id: list.first?.id)
                }
            } label: {
                Image(systemName: "play.rectangle.on.rectangle")
                    .font(.largeTitle)
            }
            .disabled(!root.itemController.hasAudio(itemId: model.id))
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
}

#Preview(traits: .mockData) {
    DetailRootView(selectedId: MockData.folderId)
}
