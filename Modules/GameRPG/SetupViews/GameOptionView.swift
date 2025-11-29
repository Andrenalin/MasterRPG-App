// @copyright André Trettin

import CoreRPG
import SwiftUI

struct GameOptionView: View {
    let root: GameRoot

    var body: some View {
        VStack {
#if os(tvOS)
            Button {
                Task {
                    await root.startDemo()
                }
            } label: {
                Label { Text("Demo", bundle: .module) } icon: { Image(systemName: "play.rectangle") }
            }
#endif
            
            Text("Start a game as", bundle: .module)
                .font(.largeTitle)

            SelectorView(root: root)
#if os(macOS)
                .padding()
#endif
            Spacer()
        }
    }
}
