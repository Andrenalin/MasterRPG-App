// @copyright André Trettin

import SwiftUI

struct ToolbarVolumeButtonView: View {
    let root: AudioRootModel
    let showsPlayer: Bool

    @State private var isVolumeSliderPresented = false

    var body: some View {
        VariableVolumeButton(volume: root.audioPlayerModel.volume) {
            isVolumeSliderPresented.toggle()
        }
        .help(Text("Adjust playback volume", bundle: .module))
#if !os(tvOS)
        .popover(isPresented: $isVolumeSliderPresented) {
            if showsPlayer {
                ToolbarAudioPlayerPopoverView(root: root)
#if os(iOS)
                    .presentationCompactAdaptation(.popover)
#endif
            } else {
                ToolbarVolumeSliderView(root: root)
#if os(iOS)
                    .presentationCompactAdaptation(.popover)
#endif
            }
        }
#endif
    }
}

#if !os(tvOS)
/// The popover of the game toolbar's volume button for the game master: the same player the
/// audio detail view shows, so the game master can also skip, seek and change the volume.
private struct ToolbarAudioPlayerPopoverView: View {
    let root: AudioRootModel

#if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
#endif

    var body: some View {
#if os(iOS)
        if horizontalSizeClass == .compact {
            ToolbarAudioPlayerCompactView(root: root)
        } else {
            ToolbarAudioPlayerFullView(root: root)
        }
#else
        ToolbarAudioPlayerFullView(root: root)
#endif
    }
}

struct ToolbarAudioPlayerFullView: View {
    let root: AudioRootModel
    var onClose: (() -> Void)?

    @ScaledMetric(relativeTo: .body) private var idealWidth = 520
    @ScaledMetric(relativeTo: .body) private var minimumWidth = 300

    var body: some View {
        AudioPlayerBarView(onClose: onClose)
            .environment(root)
            .padding()
            .frame(minWidth: minimumWidth, idealWidth: idealWidth, maxWidth: idealWidth)
    }
}

#if os(iOS)
/// The iPhone variant: the mini player in the first line, the volume slider in the second.
private struct ToolbarAudioPlayerCompactView: View {
    let root: AudioRootModel

    var body: some View {
        VStack {
            AudioPlayerMiniBarView()

            ToolbarVolumeSliderView(root: root)
        }
        .environment(root)
        .padding(.vertical)
    }
}
#endif
#endif

#Preview(traits: .mockData) {
    ToolbarVolumeButtonView(root: .preview, showsPlayer: true)
}
