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
                barContent
                    .glassEffect(.clear)
            }
        }
#elseif os(visionOS)
        barContent
#else
        GlassEffectContainer {
            barContent
                .glassEffect(.clear)
        }
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
    }
}
