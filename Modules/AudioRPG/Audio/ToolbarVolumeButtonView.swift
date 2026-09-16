// @copyright André Trettin

import SwiftUI

struct ToolbarVolumeButtonView: View {
    let root: AudioRootModel

    @State private var isVolumeSliderPresented = false

    var body: some View {
        VariableVolumeButton(volume: root.audioPlayerModel.volume) {
            isVolumeSliderPresented.toggle()
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
