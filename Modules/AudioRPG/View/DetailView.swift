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
        FileDetailEditorView(model: model, editController: root.editController, fileTypes: FileController.fileTypes) {
            FileImporterView(model: model, editController: root.editController, fileTypes: FileController.fileTypes)
        } background: {
            backgroundHeader
        } editor: {
            fileAndPlayerView

            if model.specialCategory {
                playlistView
            } else {
                Color.clear
            }
        } bottom: {
            ItemGroupItemView(model: model)
        }
        .environment(selection)
        .environment(openFileWindowModel)
        .onAppear {
            print("*** APPEAR id: \(model.id) sel: \(listModel.selected) --> parent: \(listModel.selectedParentId)")
        }
        .onDisappear {
            print("*** DISAPPEAR id: \(model.id) sel: \(listModel.selected) --> parent: \(listModel.selectedParentId)")
            listModel.resetListSelection()
            listModel.update(selection: Set())
        }
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

    var playlistView: some View {
        DetailListView(editController: root.editController, menuController: menuController, listModel: listModel.listModel(for: model.id, parentIsFolder: model.category == .folder), parentModel: model, items: model.subItems, module: AudioDataModel.typeId) { id in
            AudioRoute.detail(id)
        } row: { model in
            MainRowView(model: model)
        }
    }

    private var menuController: any ItemListContextMenuControllable {
        ContextMenuMultiController(editController: root.editController, itemController: root.itemController, listModel: listModel)
    }
}

#Preview(traits: .mockData) {
    @Previewable @Query var models: [AudioDataModel]
    @Previewable @Environment(\.modelContext) var modelContext

    DetailView(model: models[0])
        .environment(CacheItemListModel())
}
