// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct AudioDetailEditor: View {
    let editController: EditController
    let model: AudioModel
    
    @Environment(AudioRoot.self) private var root
    
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
        } headerView: { size, safeTopMargin, isInline in
            AudioDetailHeader(editController: editController, model: model, size: size, topMargin: safeTopMargin, isPlayerShown: $isPlayerShown, inline: isInline)
#if !os(macOS)
                .ignoresSafeArea(.container, edges: .top)
#endif
        } heightCalculator: { size in
            (96, 96)
        }
        .focusedSceneValue(\.selectedAudio, $model.id)
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
