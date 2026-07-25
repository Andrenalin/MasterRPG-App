// @copyright André Trettin

import CoreRPG
import SwiftUI
import CharacterRPG

struct GameOptionView: View {
    let root: GameRoot
    @Environment(\.supporterTier) private var supporterTier

    var body: some View {
        VStack {
#if os(tvOS)
            Button {
                Task {
                    await root.startDemo(supporterTier: supporterTier)
                }
            } label: {
                Label {
                    Text("Demo", bundle: .module)
                } icon: {
                    Image(systemName: "play.rectangle")
                }
            }
#endif
            
            Text("Start a game as", bundle: .module)
                .font(.largeTitle)

            SelectorView(root: root)
#if os(macOS)
                .padding()
#endif
        }
    }
}

#Preview(traits: .mockData) {
    @Previewable @State var root = GameRoot.preview
    
    ManagedNavigationStack {
        GameOptionView(root: .preview)
    }
    .environment(root.characterRoot.rootController)
}
