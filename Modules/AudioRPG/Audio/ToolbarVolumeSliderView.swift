// @copyright André Trettin

import SwiftUI

struct ToolbarVolumeSliderView: View {
    let root: AudioRootModel

    var body: some View {
        @Bindable var audioPlayerModel = root.audioPlayerModel
        VolumeSlider(volume: $audioPlayerModel.volume, minIcon: "speaker.fill", maxIcon: "speaker.wave.3.fill")
            .padding()
            .frame(minWidth: 240)
    }
}

#Preview {
    ToolbarVolumeSliderView(root: .preview)
}
