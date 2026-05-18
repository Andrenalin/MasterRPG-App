// @copyright André Trettin

import CoreRPG
import SwiftUI

struct PlayToolbarButton: View {
    let root: AudioRootModel
    let model: AudioModel
    
    var body: some View {
        Button {
            Task {
                let list = root.itemController.audioList(itemId: model.id)
                await root.audioController.add(audio: list, replace: true)
                root.audioController.togglePlay(id: list.first?.id)
            }
        } label: {
            Label {
                Text("Play", bundle: .module)
            } icon: {
                Image(systemName: "play.rectangle.on.rectangle")
            }
        }
        .disabled(!root.itemController.hasAudio(itemId: model.id))
    }
}
