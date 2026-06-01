// @copyright André Trettin

import CoreRPG
import SwiftUI

struct AudioPlayerPlaybackControls: View {
    let audioController: AudioController
    let audioPlayerModel: AudioPlayerModel

    var body: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation {
                    audioController.skipToCurrentItem(offsetBy: -1)
                }
            } label: {
                Label { Text("Previous Track", bundle: .module) } icon: { Image(systemName: "backward.fill") }
                    .labelStyle(.iconOnly)
                    .font(.title3)
                    .frame(width: 32, height: 32)
                    .contentShape(.rect) // Ensure full frame is tappable
            }
            .buttonStyle(.plain)
            .disabled(!audioPlayerModel.hasPrev)

            Button {
                withAnimation {
                    audioController.togglePlay()
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
                withAnimation {
                    audioController.skipToCurrentItem(offsetBy: 1)
                }
            } label: {
                Label { Text("Next Track", bundle: .module) } icon: { Image(systemName: "forward.fill") }
                    .labelStyle(.iconOnly)
                    .font(.title3)
                    .frame(width: 32, height: 32)
                    .contentShape(.rect) // Ensure full frame is tappable
            }
            .buttonStyle(.plain)
            .disabled(!audioPlayerModel.hasNext)
        }
        .foregroundStyle(.primary)
    }
}
