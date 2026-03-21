// @copyright André Trettin

import AudioRPG
import SwiftUI

struct MenuBarView: View {
    let audioRoot: AudioRootModel

    var body: some View {
        VStack {
            Text("Music in MasterRPG")

            Divider()

            audioRoot.viewController.viewAudioPlayer(root: audioRoot, with: nil)

        }
        .padding()
        .environment(audioRoot)
    }
}


#Preview {
    MenuBarView(audioRoot: .preview)
}
