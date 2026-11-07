// @copyright André Trettin

import CoreRPG
import SwiftUI

struct AudioPlayerBarView: View {
    @Environment(AudioRootModel.self) private var root

#if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
#endif

    @State private var viewModel = AudioPlayerBarViewModel()

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
        AudioPlayerBarContentView(viewModel: viewModel)
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

    @Environment(AudioRootModel.self) private var root

    var body: some View {
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
                isSliderVisible: $viewModel.isVolumeSliderVisible,
                onToggleMute: {
                    viewModel.toggleMute(audioPlayerModel: root.audioPlayerModel)
                }
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
