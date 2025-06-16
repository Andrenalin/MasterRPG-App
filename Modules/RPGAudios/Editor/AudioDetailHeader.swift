// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct AudioDetailHeader: View {
    let editController: EditController
    let model: AudioModel
    @Binding var isPlayerShown: Bool

    @Environment(AudioRoot.self) private var root
    @Environment(DetailHeaderModel.self) private var headerModel

    var body: some View {
        VStack {
            Image(systemName: NetworkModules.audio.icon)
                .font(.system(size: headerModel.size.height - valueFor(iOS: headerModel.topSafeAreaHeight, macOS: 16, tvOS: headerModel.topSafeAreaHeight, visionOS: headerModel.topSafeAreaHeight)))
                .frame(height: headerModel.size.height - valueFor(iOS: headerModel.topSafeAreaHeight, macOS: 16, tvOS: headerModel.topSafeAreaHeight, visionOS: headerModel.topSafeAreaHeight), alignment: .center)
                .foregroundStyle(.white)
                .opacity(0.3)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .overlay(alignment: .center) {
            @Bindable var model = model
            BlurText(text: model.name, color: .teal)
                .font(.largeTitle)
        }
#if os(iOS)
        .toolbar {
            ToolbarItem {
                if headerModel.isInline == false {
                    mainToolbarButton
                }
            }
        }
#else
        .overlay(alignment: .topTrailing) {
            mainToolbarButton
                .padding(.trailing, valueFor(iOS: 16, macOS: 16, tvOS: 16, visionOS: 24))
        }
#endif
        .padding(.top, valueFor(iOS: headerModel.topSafeAreaHeight / 2, macOS: 0, tvOS: headerModel.topSafeAreaHeight / 2, visionOS: headerModel.topSafeAreaHeight / 2))
        .frame(height: headerModel.size.height, alignment: .center)
    }
    
    private var mainToolbarButton: some View {
        ImageOverlayButton(icon: root.itemController.itemDataModel.networkModule.icon) {
            withAnimation {
                isPlayerShown.toggle()
            }
            if isPlayerShown {
                root.gameController.play(id: editController.model.id, shouldPlay: true)
            }
        }
    }
}
