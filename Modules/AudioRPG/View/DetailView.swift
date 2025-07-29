// Copy
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
            
            FileDetailEditorView(model: model, editController: root.editController, nameKeyPath: \.name, categoryKeyPath: \.category, tagsKeyPath: \.tags, descriptionKeyPath: \.information, urlKeypath: \.url, fileTypes: FileController.fileTypes) {
                FileImporterView(model: model, prominent: true)
            }

            Button {
                root.audioPlayerModel.isPlaying.toggle()
            } label: {
                Image(systemName: "play")
                    .font(.largeTitle)
            }
      
            if shouldShowBottomBar {
                VStack {
                    AudioPlayerBarView()
                }
                .padding()
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
        .tabViewBottomAccessory {
            AudioPlayerMiniBarView()
        }

//        .applyIf(!shouldShowBottomBar) {
//            $0.tabViewBottomAccessory {
//                AudioPlayerMiniBarView()
//            }
//        }
    }
    
    var shouldShowBottomBar: Bool {
#if os(iOS)
        return horizontalSizeClass != .compact
#else
        return true
#endif
    }
}

#Preview(traits: .mockData) {
    @Previewable @Query var models: [AudioDataModel]
    @Previewable @Environment(\.modelContext) var modelContext

    DetailView(model: models[0])
        .environment(CacheItemListModel())
}
