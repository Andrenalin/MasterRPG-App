// @copyright André Trettin

import CoreRPG
import SwiftUI

public extension EnvironmentValues {
    @Entry var audioPlayerUsesTabAccessory = false
}

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
            .allowsHitTesting(true) // Ensure touches are registered
        } else {
            GlassEffectContainerView {
                barContent
                    .glassEffect(.clear)
            }
            .allowsHitTesting(true) // Ensure touches are registered
        }
#elseif os(visionOS)
        barContent
            .allowsHitTesting(true)
#else
        GlassEffectContainerAll {
            barContent
                .glassEffectAll(.clear)
        }
        .allowsHitTesting(true)
#endif
    }

    private var barContent: some View {
        HStack(alignment: .center, spacing: 8) {
            AudioPlayerPlaybackControls(
                audioController: root.audioController,
                audioPlayerModel: root.audioPlayerModel
            )
            .padding(.horizontal, 8)

            AudioPlayerTimelineView(
                currentItem: root.audioPlayerModel.currentItem,
                audioController: root.audioController,
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
        }
        .padding(.vertical, 8)
        .contentShape(.rect) // Ensure the entire bar area is interactive
    }
}

#Preview(traits: .mockData) {
    AudioPlayerBarView()
}
