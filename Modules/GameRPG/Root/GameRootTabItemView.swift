// @copyright André Trettin

import CoreRPG
import SwiftUI

struct GameRootTabItemView: View {
    let root: GameRoot
    
#if os(macOS) || os(visionOS)
    @Environment(\.openWindow) private var openWindow
#endif
    
    var body: some View {
        GameRootTabView(root: root)
#if os(visionOS)
        .ornament(attachmentAnchor: .scene(.trailing)) {
            Button {
                withAnimation {
                    openWindow(id: WindowIdentifier.editor.rawValue)
                }
            } label: {
                Label {
                    Text(NetworkModules.editor.title)
                } icon: {
                    Image(systemName: NetworkModules.editor.icon)
                }
                
            }
            Button {
                withAnimation {
                    openWindow(id: WindowIdentifier.search.rawValue)
                }
            } label: {
                Label {
                    Text(NetworkModules.search.title)
                } icon: {
                    Image(systemName: NetworkModules.search.icon)
                }
                
            }
            Button {
                withAnimation {
                    openWindow(id: WindowIdentifier.settings.rawValue)
                }
            } label: {
                Label {
                    Text(NetworkModules.setting.title)
                } icon: {
                    Image(systemName: NetworkModules.setting.icon)
                }
                
            }
        }
#endif
    }
}

struct GameRootTabView: View {
    let root: GameRoot

#if os(macOS) || os(visionOS)
    @Environment(\.openWindow) private var openWindow
#endif
    
    var body: some View {
        ZStack {
            MeshAnimationView()
                .ignoresSafeArea()
                .opacity(0.5)
            
            ScrollView {
#if os(macOS)
                Button {
                    withAnimation {
                        openWindow(id: WindowIdentifier.editor.rawValue)
                    }
                } label: {
                    Label { Text("Editor Window", bundle: .module) } icon: { Image(systemName: "square.and.pencil") }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .trailing)
#endif
                
                GameOptionView(root: root)
            }
            .task {
                await root.networkStore.setup(gameModel: root.gameModel)
            }
        }
    }
}

#Preview {
    GameRootTabItemView(root: .preview)
        .environment(\.wideMode, .small)
        .environment(AppSettingsModel())
}
