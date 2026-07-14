// @copyright André Trettin

import SwiftUI

struct ToolbarVolumeButtonView: View {
    let root: AudioRootModel

    @State private var isVolumeSliderPresented = false

    var body: some View {
        Button {
            isVolumeSliderPresented.toggle()
        } label: {
            Label {
                Text("Volume", bundle: .module)
            } icon: {
                Image(
                    systemName: "volume.3",
                    variableValue: root.audioPlayerModel.volume
                )
                .symbolRenderingMode(.hierarchical)
                .symbolEffect(.bounce, value: root.audioPlayerModel.volume)
            }
            .labelStyle(.iconOnly)
        }
        .help(Text("Adjust playback volume", bundle: .module))
        .popover(isPresented: $isVolumeSliderPresented) {
#if os(iOS)
            ToolbarVolumeSliderView(root: root)
                .presentationCompactAdaptation(.popover)
#else
            ToolbarVolumeSliderView(root: root)
#endif
        }
    }
}

private struct ToolbarVolumeSliderView: View {
    let root: AudioRootModel

    var body: some View {
        @Bindable var audioPlayerModel = root.audioPlayerModel

        Slider(value: $audioPlayerModel.volume, in: 0...1) {
            Text("Volume", bundle: .module)
        } minimumValueLabel: {
            Image(systemName: "speaker.fill")
        } maximumValueLabel: {
            Image(systemName: "speaker.wave.3.fill")
        }
        .padding()
        .frame(minWidth: 240)
    }
}

#Preview {
    ToolbarVolumeButtonView(root: .preview)
}
