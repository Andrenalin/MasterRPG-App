// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI

struct DetailView: View {
    let model: AudioDataModel
    
#if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
#endif
    
    @Environment(AudioRootModel.self) private var root
    @Environment(ListModel.self) private var listModel

    @State private var selection = GroupItemSelectionModel()

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear

            FileDetailEditorView(model: model, editController: root.editController, name: \.name, category: \.category, tags: \.tags, description: \.information, url: \.url, specialCategory: \.specialCategory, fileTypes: FileController.fileTypes) {
                FileImporterView(model: model, editController: root.editController, fileTypes: FileController.fileTypes)
            } editor: {
                fileAndPlayerView
                
                if model.specialCategory {
                    playlistView
                        .safeAreaBar(edge: .bottom) {
                            if shouldShowBottomBar {
                                AudioPlayerBarView()
                                    .opacity(0)
                            }
                        }
                }
            }
            
            if shouldShowBottomBar {
                VStack {
                    if !model.specialCategory {
                        carouselView
                            .padding(.bottom)
                    }
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
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
#if !os(tvOS)
        .toolbar(removing: .title)
#endif
    }
}

private extension DetailView {
    var shouldShowBottomBar: Bool {
#if os(iOS)
        return horizontalSizeClass != .compact
#else
        return true
#endif
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

    @ViewBuilder
    var carouselView: some View {
        if model.url != nil {
            CarouselItemView(model: model, editController: root.editController, selection: selection) {
                AudioGroupItem()
            }
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .transition(.move(edge: .bottom))
        }
    }

}

#Preview(traits: .mockData) {
    @Previewable @Query var models: [AudioDataModel]
    @Previewable @Environment(\.modelContext) var modelContext
    
    DetailView(model: models[0])
        .environment(CacheItemListModel())
}


struct AudioGroupItem: View {
    @Environment(\.modelContext) var modelContext
    @Environment(GroupItemSelectionModel.self) var selection

    var body: some View {
        VStack {
            if let item = item {
                Text(item.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Image(systemName: item.category.icon)
                    .imageScale(.large)
                    .font(.title)
            }
        }
        .padding()
    }

    var item: AudioDataModel? {
        guard let id = selection.selectedItem else { return nil }
        return AudioDataModel.model(modelContext: modelContext, id: id)
    }
}
