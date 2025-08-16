// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI

struct DetailView: View {
    let model: AudioDataModel

    @Environment(AudioRootModel.self) private var root
    @Environment(ListModel.self) private var listModel
    
    @State private var selection = GroupItemSelectionModel()
    @State private var openFileWindowModel = OpenFileWindowModel()

    var body: some View {
        FileDetailEditorView(model: model, editController: root.editController, menuController: menuController, fileTypes: FileController.fileTypes) {
            DetailRoute.detail($0)
        } importer: {
            FileImporterView(model: model, editController: root.editController, fileTypes: FileController.fileTypes)
        } background: {
            backgroundHeader
        } editor: {
            fileAndPlayerView
            
            if !model.specialCategory {
                Color.clear
            }
        } row: { itemId in
            if let model = root.itemController.modelSync(for: itemId) {
                MainRowView(model: model)
            }
        } bottom: {
            ItemGroupItemView(model: model)
        } inspector: {
            LinkRootView(isInspector: true)
        }
        .environment(selection)
        .environment(openFileWindowModel)
    }
}

private extension DetailView {
    var backgroundHeader: some View {
        Group {
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
        .background {
                ConcentricRectangle().fill(AudioDataModel.typeId.color.gradient)
                    .ignoresSafeArea(edges: .top)
                    .backgroundExtensionEffect()
            }
    }

    var fileAndPlayerView: some View {
        HStack {
            HStack {
                FileImporterView(model: model, editController: root.editController, fileTypes: FileController.fileTypes, isProminent: false)

                Text(model.url?.absoluteString ?? "No file is set")
                    .frame(maxWidth: .infinity, alignment: .leading)

            }
            .opacity(model.specialCategory ? 0 : 1)

            Button {
                Task {
                    let list = model.audioList
                    await root.audioController.add(audio: list, replace: true)
                    root.audioController.togglePlay(id: list.first?.id)
                }
            } label: {
                Image(systemName: "play")
                    .font(.largeTitle)
            }
            .disabled(!model.hasAudio)
        }
        .padding()
    }

    var menuController: any ItemListContextMenuControllable {
        ContextMenuMultiController(editController: root.editController, itemController: root.itemController, listModel: listModel)
    }
}

#Preview(traits: .mockData) {
    @Previewable @Query var models: [AudioDataModel]

    DetailView(model: models[0])
}
