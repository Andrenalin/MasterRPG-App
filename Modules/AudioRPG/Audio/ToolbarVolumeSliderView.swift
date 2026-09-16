// @copyright André Trettin

import SwiftUI

struct ToolbarVolumeSliderView: View {
    let root: AudioRootModel

    var body: some View {
        @Bindable var audioPlayerModel = root.audioPlayerModel
#if os(tvOS)
        EmptyView()
#else
        VolumeSlider(volume: $audioPlayerModel.volume, minIcon: "speaker.fill", maxIcon: "speaker.wave.3.fill")
            .padding()
            .frame(minWidth: 240)
#endif
    }
}

#Preview {
    ToolbarVolumeSliderView(root: .preview)
}
