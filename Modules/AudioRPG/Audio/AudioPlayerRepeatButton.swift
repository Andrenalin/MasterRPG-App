// @copyright André Trettin

import CoreRPG
import SwiftUI

#Preview(traits: .mockData) {
    @Previewable @Environment(AudioRootModel.self) var root
    AudioPlayerRepeatButton(audioPlayerModel: root.audioPlayerModel)
        .padding()
}

/// Enables / disables the playlist loop (`AudioPlayerModel.repeatPlayList`) of the audio players.
struct AudioPlayerRepeatButton: View {
    @Bindable var audioPlayerModel: AudioPlayerModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            withAnimation(.default.reduced(if: reduceMotion)) {
                audioPlayerModel.repeatPlayList.toggle()
            }
        } label: {
            Label {
                Text("Repeat Playlist", bundle: .module)
            } icon: {
                Image(systemName: audioPlayerModel.repeatPlayList ? "repeat.circle.fill" : "repeat.circle")
                    .contentTransition(.symbolEffect(.replace))
            }
            .labelStyle(.iconOnly)
            .font(.title3)
            .foregroundStyle(audioPlayerModel.repeatPlayList ? Color.accentColor : .secondary)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityValue(
            audioPlayerModel.repeatPlayList
                ? Text("Enabled", bundle: .module)
                : Text("Disabled", bundle: .module)
        )
    }
}
