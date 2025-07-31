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
    
    var body: some View {
        ZStack(alignment: .top) {
            Color.clear
            
            FileDetailEditorView(model: model, editController: root.editController, name: \.name, category: \.category, tags: \.tags, description: \.information, url: \.url, specialCategory: \.specialCategory, fileTypes: FileController.fileTypes) {
                FileImporterView(model: model, editController: root.editController, fileTypes: FileController.fileTypes)
            } editor: {
                fileAndPlayerView
                
                if model.specialCategory {
                    playlistView
                }
            }
            
            
            if shouldShowBottomBar {
                VStack {
                    AudioPlayerBarView()
                }
                .padding()
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
    }
}

private extension DetailView {
    func addLinks(links: [LinkData]) {
        links.forEach { link in
            guard link.module == AudioDataModel.typeId else { return }
            withAnimation { root.editController.addItem(itemId: link.itemId, in: model) }
        }
    }
    
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
        List {
            if model.entryModels.isEmpty {
                HStack {
                    Text("Drop audio here to add to the playlist")
                        .padding(20)
                        .overlay {
                            RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.accentColor, lineWidth: 2)
                        }
                }
#if !os(tvOS)
                .dropDestination(for: LinkData.self, isEnabled: model.specialCategory) { items, session in
                    guard !items.isEmpty else { return }
                    addLinks(links: items)
                }
#endif
                .frame(maxWidth: .infinity)
            }
            
            ForEach(model.entryModels) { entry in
                if let model = AudioDataModel.model(modelContext: model.modelContext, id: entry.itemId) {
                    MainRowView(model: model)
                }
            }
#if !os(tvOS)
            .dropDestination(for: LinkData.self, isEnabled: model.specialCategory) { items, session in
                guard !items.isEmpty else { return }
                addLinks(links: items)
            }
#endif
        }
        
    }
}

#Preview(traits: .mockData) {
    @Previewable @Query var models: [AudioDataModel]
    @Previewable @Environment(\.modelContext) var modelContext
    
    DetailView(model: models[0])
        .environment(CacheItemListModel())
}
