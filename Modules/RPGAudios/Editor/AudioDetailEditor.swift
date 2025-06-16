// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct AudioDetailEditor: View {
    let editController: EditController
    let model: AudioModel
    
    @Environment(AudioRoot.self) private var root

    @State private var detailHeaderModel = DetailHeaderModel()
    @State private var externalHeaderModel = ExternalHeaderModel()
    @State private var isPlayerShown: Bool = false

    var body: some View {
        @Bindable var model = model
        DetailEditor(editController: editController) {
            audioHeaderPlayerView

            HeaderEditor(editController: editController)
            
            Section {
                AudioEditor(editController: editController)
                
                FileLocationEditor(editController: editController, fileStore: root.fileUrlDataController, fileUrlBinding: $model.fileUrl)
                
            } header: {
#if os(macOS)
                Divider()
                    .padding(.top)
#endif
                Text("Audio", bundle: .module)
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            
            AudiosSectionEditor(editController: editController)
        } headerView: {
            AudioDetailHeader(editController: editController, model: model, isPlayerShown: $isPlayerShown)
#if !os(macOS)
                .ignoresSafeArea(.container, edges: .top)
#endif
        }
        .focusedSceneValue(\.selectedAudio, $model.id)
        .environment(detailHeaderModel)
        .environment(externalHeaderModel)
    }

    var audioHeaderPlayerView: some View {
        Section {
            if isPlayerShown {
                AudioPlayerView()
                    .transition(.slide)
                    .animation(.easeInOut, value: isPlayerShown)
            }
        } footer: {
#if os(macOS)
            if isPlayerShown {
                Divider()
                    .padding(.bottom, 20)
            }
#endif
        }
    }
}

#Preview {
    AudioDetailEditor(editController: .preview, model: .preview)
        .environment(AudioRoot.preview)
        .environment(ListModel.preview)
        .environment(SelectionSheetLinkModel())
}
