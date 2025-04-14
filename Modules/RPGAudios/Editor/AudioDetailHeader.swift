// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct AudioDetailHeader: View {
    let editController: EditController
    let model: AudioModel
    let size: CGSize
    let topMargin: CGFloat
    @Binding var isPlayerShown: Bool
    let inline: Bool
    
    @Environment(AudioRoot.self) private var root
    
    var body: some View {
        VStack {
            Image(systemName: NetworkModules.audio.icon)
                .font(.system(size: size.height - valueFor(iOS: topMargin, macOS: 16, tvOS: topMargin, visionOS: topMargin)))
                .frame(height: size.height - valueFor(iOS: topMargin, macOS: 16, tvOS: topMargin, visionOS: topMargin), alignment: .center)
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
                if inline == false {
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
        .padding(.top, valueFor(iOS: topMargin / 2, macOS: 0, tvOS: topMargin / 2, visionOS: topMargin / 2))
        .frame(height: size.height, alignment: .center)
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
