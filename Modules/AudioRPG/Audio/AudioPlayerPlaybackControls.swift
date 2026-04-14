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
                Label("Previous Track", systemImage: "backward.fill")
                    .labelStyle(.iconOnly)
                    .font(.title3)
                    .frame(width: 32, height: 32)
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
                .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .disabled(audioPlayerModel.playList.isEmpty)

            Button {
                withAnimation {
                    audioController.skipToCurrentItem(offsetBy: 1)
                }
            } label: {
                Label("Next Track", systemImage: "forward.fill")
                    .labelStyle(.iconOnly)
                    .font(.title3)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .disabled(!audioPlayerModel.hasNext)
        }
        .foregroundStyle(.primary)
    }
}
