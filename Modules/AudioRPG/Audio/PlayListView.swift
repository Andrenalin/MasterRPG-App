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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        @Bindable var model = root.audioController.model
        VStack(alignment: .leading) {
            ForEach(model.playList) { audio in
                HStack {
                    Button {
                        if appGameStateModel.isGameRunning {
                            networkActions?.game(root.gameController.requestPlay(id: audio.id), .playAudio, nil)
                        } else {
                            root.audioController.togglePlay(id: audio.id)
                        }
                    } label: {
                        HStack {
                            Text(verbatim: audio.title)
                                .font(.caption)

                            Spacer()

                            Text(verbatim: PlayerTime(elapsedTime: audio.duration.seconds, remainingTime: 0).elapsedText)
                                .font(.caption)
                                .bold()
                                .monospaced()
                        }
                        .rowEditColor(backgroundColor: model.currentId == audio.id ? .teal : .blue)
                    }
                    .borderLessTVButtonStyle()

                    Button(role: .destructive) {
                        if appGameStateModel.isGameRunning && root.audioController.model.isPlaying && root.audioController.model.currentId == audio.id {
                            networkActions?.game(root.gameController.requestPlay(id: audio.id), .playAudio, nil)
                        }
                        withAnimation(reduceMotion ? nil : .default) {
                            root.audioController.removeAudio(id: audio.id)
                        }
                    } label: {
                        Label {
                            Text("Delete Audio", bundle: .module)
                        } icon: {
                            Image(systemName: "trash")
                        }
                        .labelStyle(.iconOnly)
                        .imageScale(.large)
                        .foregroundStyle(.red)
                    }
                    .frame(minWidth: 44, minHeight: 44)
                    .borderLessTVButtonStyle()
                }
            }
        }
    }
}
