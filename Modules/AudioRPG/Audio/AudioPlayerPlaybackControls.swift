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

    var body: some View {
        HStack(spacing: 8) {
            AudioTransportButton(kind: .previous, side: 44)
            AudioTransportButton(kind: .playPause, font: .title2, side: 44)
            AudioTransportButton(kind: .next, side: 44)
            AudioPlayerRepeatButton(audioPlayerModel: audioPlayerModel)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }
}
