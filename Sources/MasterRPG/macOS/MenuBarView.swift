// @copyright André Trettin

import RPGAudios
import SwiftUI

struct MenuBarView: View {
    let audioRoot: AudioRoot

    var body: some View {
        VStack {
            Text("Music in MasterRPG")
                .padding()
            Divider()

            audioRoot.viewController.viewAudioPlayer(with: nil)
                .padding()
        }
    }
}

#Preview {
    MenuBarView(audioRoot: .preview)
}
