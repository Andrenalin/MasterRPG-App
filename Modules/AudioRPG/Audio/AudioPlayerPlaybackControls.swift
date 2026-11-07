// @copyright André Trettin

import CoreRPG
import SwiftUI

#Preview(traits: .mockData) {
    @Previewable @Environment(AudioRootModel.self) var root
    AudioPlayerPlaybackControls(audioPlayerModel: root.audioPlayerModel)
        .padding()
}

struct AudioPlayerPlaybackControls: View {
    let audioPlayerModel: AudioPlayerModel

    @Environment(AudioRootModel.self) private var root
    @Environment(\.networkActions) private var networkActions
    @Environment(AppGameStateModel.self) private var appGameStateModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(.default.reduced(if: reduceMotion)) {
                    root.skip(offsetBy: -1, isGameRunning: appGameStateModel.isGameRunning, networkActions: networkActions)
                }
            } label: {
                Label { Text("Previous Track", bundle: .module) } icon: { Image(systemName: "backward.fill") }
                    .labelStyle(.iconOnly)
                    .font(.title3)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(.rect) // Ensure full frame is tappable
            }
            .buttonStyle(.plain)
            .disabled(!audioPlayerModel.hasPrev)

            Button {
                withAnimation(.default.reduced(if: reduceMotion)) {
                    root.togglePlayback(isGameRunning: appGameStateModel.isGameRunning, networkActions: networkActions)
                }
            } label: {
                Label(
                    audioPlayerModel.isPlaying ? "Pause" : "Play",
                    systemImage: audioPlayerModel.isPlaying ? "pause.fill" : "play.fill"
                )
                .labelStyle(.iconOnly)
                .font(.title2)
                .contentTransition(.symbolEffect(.replace.magic(fallback: .replace)))
                .frame(width: 44, height: 44) // Larger tap target for primary button
                .contentShape(.rect) // Ensure full frame is tappable
            }
            .buttonStyle(.plain)
            .disabled(audioPlayerModel.playList.isEmpty)

            Button {
                withAnimation(.default.reduced(if: reduceMotion)) {
                    root.skip(offsetBy: 1, isGameRunning: appGameStateModel.isGameRunning, networkActions: networkActions)
                }
            } label: {
                Label { Text("Next Track", bundle: .module) } icon: { Image(systemName: "forward.fill") }
                    .labelStyle(.iconOnly)
                    .font(.title3)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(.rect) // Ensure full frame is tappable
            }
            .buttonStyle(.plain)
            .disabled(!audioPlayerModel.hasNext)

            AudioPlayerRepeatButton(audioPlayerModel: audioPlayerModel)
        }
        .foregroundStyle(.primary)
    }
}
