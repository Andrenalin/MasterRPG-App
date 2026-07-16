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
#if !os(tvOS)
        .popover(isPresented: $isVolumeSliderPresented) {
#if os(iOS)
            ToolbarVolumeSliderView(root: root)
                .presentationCompactAdaptation(.popover)
#else
            ToolbarVolumeSliderView(root: root)
#endif
        }
#endif
    }
}

#Preview {
    ToolbarVolumeButtonView(root: .preview)
}
