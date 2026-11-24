// @copyright André Trettin

import CoreRPG
import SwiftUI

struct AudioPlayerBarView: View {
    @Environment(AudioRootModel.self) private var root

#if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
#endif

    @State private var viewModel = AudioPlayerBarViewModel()

    /// A close button for a player that stands in a panel of its own. On visionOS it ends the
    /// row of the position slider, under the volume button.
    private let onClose: (() -> Void)?

    init(onClose: (() -> Void)? = nil) {
        self.onClose = onClose
    }

    var body: some View {
#if os(iOS)
        if horizontalSizeClass == .compact {
            GlassEffectContainerView {
                AudioPlayerMiniBarView()
                    .glassEffect(.clear)
            }
        } else {
            GlassEffectContainerView {
                AudioPlayerBarContentView(viewModel: viewModel)
                    .glassEffect(.clear)
            }
        }
#elseif os(visionOS)
        AudioPlayerBarContentView(viewModel: viewModel, onClose: onClose)
#else
        GlassEffectContainerAll {
            AudioPlayerBarContentView(viewModel: viewModel)
                .glassEffectAll(.clear)
        }
#endif
    }

}

#Preview(traits: .mockData) {
    AudioPlayerBarView()
}

// MARK: - Extracted subviews (CODE_AUDIT §8.3)

private struct AudioPlayerBarContentView: View {
    @Bindable var viewModel: AudioPlayerBarViewModel
    var onClose: (() -> Void)?

    @Environment(AudioRootModel.self) private var root

    var body: some View {
#if os(visionOS)
        // No pointer reveals a hidden scrubber here (there is no hover): the position slider is
        // a row of its own under the controls, as in the Music app, so it can always be pinched
        // and dragged to move forward or backward in the song.
        VStack(spacing: 4) {
            controlsRow

            HStack(spacing: 8) {
                AudioPlayerPersistentScrubberView(audioPlayerModel: root.audioPlayerModel)

                if let onClose {
                    Button(action: onClose) {
                        Label {
                            Text("Close", bundle: .module)
                        } icon: {
                            Image(systemName: "xmark")
                        }
                    }
                    .labelStyle(.iconOnly)
                    .buttonBorderShape(.circle)
                }
            }
            .padding(.horizontal, 8)
        }
#else
        controlsRow
#endif
    }

    private var controlsRow: some View {
        HStack(alignment: .center, spacing: 8) {
            AudioPlayerPlaybackControls(audioPlayerModel: root.audioPlayerModel)
            .padding(.horizontal, 8)

            AudioPlayerTimelineView(
                currentItem: root.audioPlayerModel.currentItem,
                audioPlayerModel: root.audioPlayerModel,
                viewModel: viewModel
            )
            .frame(maxWidth: .infinity, alignment: .leading)

            AudioPlayerVolumeControl(
                audioPlayerModel: root.audioPlayerModel,
                isSliderVisible: $viewModel.isVolumeSliderVisible
            )
            .padding(.horizontal, 8)
#if os(iOS)
            // The only route picker the player offers: AirPlay is declared as a background mode.
            // See CODE_AUDIT_Audio2 §8.1.
            RoutePickerView()
                .frame(width: 32, height: 32)
                .padding(.trailing, 8)
#endif
        }
        .padding(.vertical, 8)
        .contentShape(.rect) // Ensure the entire bar area is interactive
    }
}
