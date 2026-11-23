// @copyright André Trettin

import CoreRPG
import SwiftUI

#Preview(traits: .mockData) {
    @Previewable @Environment(AudioRootModel.self) var root
    PlayToolbarButton(root: root, model: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[0]))
}

struct PlayToolbarButton: View {
    let root: AudioRootModel
    let model: AudioModel

    @Environment(\.networkActions) private var networkActions
    @Environment(AppGameStateModel.self) private var appGameStateModel: AppGameStateModel?

    var body: some View {
        Button {
            Task {
                await root.playItem(id: model.id, isGameRunning: appGameStateModel?.isGameRunning == true, networkActions: networkActions)
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
