// @copyright André Trettin

import CoreRPG
import SwiftUI

struct SelectObserverGameView: View {
    let root: GameRoot
    
    var body: some View {
        VStack {
            GroupBoxTV(isCard: true, withoutGroup: true) {
                VStack {
                    Text("As an observer you can join any hosted game in the local network. All observers does not have a player pin nor dice to roll. They are invisible and show only the game view without any interaction in the game.", bundle: .module)
                        .lineLimit(10)
                }
            } label: {
                Label {
                    Text("Observe a game", bundle: .module)
                        .font(.headline)
                } icon: {
                    Image(systemName: "eye.fill")
                        .imageScale(.large)
                }
            }
            
            if let playerNetworkController = root.networkStore.model.playerStore {
                BrowserView(root: root, playerNetworkControllable: playerNetworkController)
                    .environment(\.browserMode, .observer)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }
}

#Preview {
    SelectObserverGameView(root: .preview)
}
