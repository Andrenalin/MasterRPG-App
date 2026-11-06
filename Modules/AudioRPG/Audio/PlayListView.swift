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
                        root.playOrRequest(id: audio.id, isGameRunning: appGameStateModel.isGameRunning, networkActions: networkActions)
                    } label: {
                        HStack {
                            Text(verbatim: audio.title)
                                .font(.caption)

                            Spacer()

                            Text(verbatim: PlayerTime.formatted(time: audio.duration.seconds))
                                .font(.caption)
                                .bold()
                                .monospaced()
                        }
                        .rowEditColor(backgroundColor: model.currentId == audio.id ? .teal : .blue)
                    }
                    .borderLessTVButtonStyle()

                    Button(role: .destructive) {
                        withAnimation(reduceMotion ? nil : .default) {
                            root.remove(id: audio.id, isGameRunning: appGameStateModel.isGameRunning, networkActions: networkActions)
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
