// @copyright André Trettin

import AndrenalinKit
import SwiftUI
import CoreMedia

struct PlayListView: View {
    let root: AudioRootModel
    
    @Environment(\.networkActions) private var networkActions
    @Environment(\.showGame) private var showGame

    var body: some View {
        @Bindable var model = root.audioController.model
        VStack(alignment: .leading) {
            ForEach(model.playList) { audio in
                HStack {
                    Button {
                        if showGame {
                            networkActions?.game(root.gameController.requestPlay(id: audio.id), .generic)
                        } else {
                            root.audioController.togglePlay(id: audio.id)
                        }
                    } label: {
                        HStack {
                            Text(audio.title)
                                .font(.caption)

                            Spacer()

                            Text(PlayerTime(elapsedTime: audio.duration.seconds, remainingTime: 0).elapsedText)
                                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        }
                        .rowEditColor(backgroundColor: model.currentId == audio.id ? .teal : .blue)
                    }
                    .borderLessTVBottonStyle()

                    Button(role: .destructive) {
                        if showGame && root.audioController.model.isPlaying && root.audioController.model.currentId == audio.id {
                            networkActions?.game(root.gameController.requestPlay(id: audio.id), .generic)
                        }
                        withAnimation { root.audioController.removeAudio(id: audio.id) }
                    } label: {
                        Image(systemName: "trash")
                            .imageScale(.large)
                            .foregroundStyle(.red)
                    }
                    .borderLessTVBottonStyle()
                }
            }
        }
    }
}
