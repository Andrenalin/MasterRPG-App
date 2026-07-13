// @copyright André Trettin

import CoreRPG
import SwiftUI
import CoreMedia

#Preview(traits: .mockData) {
    @Previewable @Environment(AudioRootModel.self) var root
    PlayListView(root: root)
        .padding()
}

struct PlayListView: View {
    let root: AudioRootModel
    
    @Environment(\.networkActions) private var networkActions
    @Environment(AppGameStateModel.self) private var appGameStateModel

    var body: some View {
        @Bindable var model = root.audioController.model
        VStack(alignment: .leading) {
            ForEach(model.playList) { audio in
                HStack {
                    Button {
                        if appGameStateModel.isGameRunning {
                            networkActions?.game(root.gameController.requestPlay(id: audio.id), .generic, nil)
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
                        if appGameStateModel.isGameRunning && root.audioController.model.isPlaying && root.audioController.model.currentId == audio.id {
                            networkActions?.game(root.gameController.requestPlay(id: audio.id), .generic, nil)
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
