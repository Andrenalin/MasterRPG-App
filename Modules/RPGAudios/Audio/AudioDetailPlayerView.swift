// @copyright André Trettin

import AndrenalinKit
import AVKit
import SwiftUI

struct AudioDetailPlayerView: View {
    let item: ItemRowTreeModel
    
    @Environment(AudioRoot.self) private var root
    @Environment(\.routeActions) private var routeActions

    var body: some View {
        ScrollView {
            AudioPlayerView()
                .padding(.top, 64)
                .onAppear {
                    root.gameController.play(id: item.model.itemId, shouldPlay: true)
                }
                .overlay(alignment: .topTrailing) {
                    Button {
                        routeActions.routePage(root.itemController.itemDataModel.networkModule, item.model.itemId, item.model.entryId)
                    } label: {
                        Image(systemName: root.itemController.itemDataModel.networkModule.icon)
                    }
                    .padding()
                }
                .padding()
        }
    }
}
