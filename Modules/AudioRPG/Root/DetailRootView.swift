// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI

struct DetailRootView: View {
    @Environment(AudioRootModel.self) private var root
    
    var body: some View {
        CoreRPG.DetailRootView(moveDetails: true) {
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
}

private extension DetailRootView {
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
                Image(systemName: "play")
                    .font(.largeTitle)
            }
            .disabled(!root.itemController.hasAudio(itemId: model.id))
        }
        .padding()
    }

    var selectedModel: ItemDataModel? {
        root.listControllable.listModel.selectedModel
    }
}

#Preview(traits: .mockData) {
    @Previewable @Query var models: [ItemDataModel]
    @Previewable @Environment(AudioRootModel.self) var root
    
    DetailRootView().onAppear {
        root.listControllable.listModel.set(selectedItemId: models.first!.id)
    }
}
