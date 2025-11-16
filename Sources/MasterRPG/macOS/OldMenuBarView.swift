// @copyright André Trettin

import RPGAudios
import SwiftUI

struct OldMenuBarView: View {
    let audioRoot: AudioRootModel

    var body: some View {
        VStack {
            Text("Music in MasterRPG")
                .padding()
            Divider()

            audioRoot.viewController.viewAudioPlayer(root: audioRoot, with: nil)
                .padding()
        }
    }
}

#Preview {
    OldMenuBarView(audioRoot: .preview)
}
