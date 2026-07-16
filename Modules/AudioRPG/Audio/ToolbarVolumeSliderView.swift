// @copyright André Trettin

import SwiftUI

struct ToolbarVolumeSliderView: View {
    let root: AudioRootModel

    var body: some View {
        @Bindable var audioPlayerModel = root.audioPlayerModel
#if os(tvOS)
        EmptyView()
#else
        Slider(value: $audioPlayerModel.volume, in: 0...1) {
            Text("Volume", bundle: .module)
        } minimumValueLabel: {
            Image(systemName: "speaker.fill")
        } maximumValueLabel: {
            Image(systemName: "speaker.wave.3.fill")
        }
        .padding()
        .frame(minWidth: 240)
#endif
    }
}

#Preview {
    ToolbarVolumeSliderView(root: .preview)
}
