// @copyright André Trettin

import CoreRPG
import SwiftUI

#Preview(traits: .mockData) {
    @Previewable @Environment(AudioRootModel.self) var root
    @Previewable @State var viewModel = AudioPlayerBarViewModel()
    AudioPlayerTimelineView(
        currentItem: root.audioPlayerModel.currentItem,
        audioPlayerModel: root.audioPlayerModel,
        viewModel: viewModel
    )
    .padding()
}

struct AudioPlayerTimelineView: View {
    let currentItem: PlaylistItem?
    let audioPlayerModel: AudioPlayerModel
    @Bindable var viewModel: AudioPlayerBarViewModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    fileprivate enum Constants {
        static let contentHeight: CGFloat = 44
        static let horizontalSpacing: CGFloat = 4
        static let albumArtSize: CGFloat = 44
        static let albumArtCornerRadius: CGFloat = 4
        static let progressBarScale: CGFloat = 0.4
        static let blurRadius: CGFloat = 8
        static let hoverOpacity: CGFloat = 0.3
        static let hoverSpring = Animation.spring(response: 0.25, dampingFraction: 0.8)
    }

    var body: some View {
        AudioPlayerTimelineLayersView(
            currentItem: currentItem,
            audioPlayerModel: audioPlayerModel,
            viewModel: viewModel,
            showScrubber: showScrubber,
            hideScrubber: hideScrubber
        )
    }

    private func showScrubber() {
        withAnimation(reduceMotion ? nil : Constants.hoverSpring) {
            viewModel.isScrubberVisible = true
        }
    }

    private func hideScrubber() {
        withAnimation(reduceMotion ? nil : Constants.hoverSpring) {
            viewModel.isScrubberVisible = false
        }
    }
}

// MARK: - Extracted subviews (CODE_AUDIT §8.3)
//
// Each gives SwiftUI its own diffing boundary, instead of the previous computed
// `some View` properties on `AudioPlayerTimelineView` itself that all re-evaluated
// whenever any part of `AudioPlayerTimelineView`'s body did.

/// The timeline: the title and artwork, the progress bar and the scrubber over them. How the
/// scrubber is revealed is the platform's: a tap on iOS, hovering elsewhere
/// (`AudioPlayerTimelineRevealTrigger`, `AudioPlayerTimelineHoverRevealModifier`).
private struct AudioPlayerTimelineLayersView: View {
    let currentItem: PlaylistItem?
    let audioPlayerModel: AudioPlayerModel
    let viewModel: AudioPlayerBarViewModel
    let showScrubber: () -> Void
    let hideScrubber: () -> Void

    var body: some View {
        AudioPlayerTimelineRevealTrigger(
            currentItem: currentItem,
            audioPlayerModel: audioPlayerModel,
            viewModel: viewModel,
            showScrubber: showScrubber
        )
            .overlay(alignment: .bottom) {
                AudioPlayerTimelineProgressOverlayView(audioPlayerModel: audioPlayerModel, viewModel: viewModel)
            }
            .overlay {
                AudioPlayerTimelineScrubberOverlayView(
                    audioPlayerModel: audioPlayerModel,
                    viewModel: viewModel,
                    hideScrubber: hideScrubber
                )
            }
            .modifier(AudioPlayerTimelineHoverRevealModifier(viewModel: viewModel))
            .task(id: currentItem?.id) {
                await viewModel.loadAlbumArtwork(for: currentItem)
            }
    }
}

/// The content of the timeline and what reveals the scrubber from it on iOS: a tap anywhere.
/// Elsewhere the content only stops taking hits while the scrubber is shown.
private struct AudioPlayerTimelineRevealTrigger: View {
    let currentItem: PlaylistItem?
    let audioPlayerModel: AudioPlayerModel
    let viewModel: AudioPlayerBarViewModel
    let showScrubber: () -> Void

    var body: some View {
        #if os(iOS)
        if viewModel.isVolumeSliderVisible {
            // The slider takes drags itself: no tap target around it.
            AudioPlayerTimelineContentLayerView(currentItem: currentItem, audioPlayerModel: audioPlayerModel, viewModel: viewModel)
        } else {
            Button {
                showScrubber()
            } label: {
                AudioPlayerTimelineContentLayerView(currentItem: currentItem, audioPlayerModel: audioPlayerModel, viewModel: viewModel)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Show Playback Controls", bundle: .module))
        }
        #else
        AudioPlayerTimelineContentLayerView(currentItem: currentItem, audioPlayerModel: audioPlayerModel, viewModel: viewModel)
            .allowsHitTesting(!viewModel.isScrubberShown)
        #endif
    }
}

/// Reveals the scrubber while the pointer is over the timeline (not on iOS, which taps, and
/// not on tvOS, which has no pointer).
private struct AudioPlayerTimelineHoverRevealModifier: ViewModifier {
    let viewModel: AudioPlayerBarViewModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        #if os(iOS) || os(tvOS) || os(visionOS)
        content
        #else
        content
            .contentShape(.rect)
            .onHover { hovering in
                withAnimation(reduceMotion ? nil : AudioPlayerTimelineView.Constants.hoverSpring) {
                    viewModel.isScrubberVisible = hovering
                }
            }
        #endif
    }
}

private struct AudioPlayerTimelineContentLayerView: View {
    let currentItem: PlaylistItem?
    @Bindable var audioPlayerModel: AudioPlayerModel
    let viewModel: AudioPlayerBarViewModel

    var body: some View {
        HStack(spacing: AudioPlayerTimelineView.Constants.horizontalSpacing) {
            AlbumArtworkView(
                artwork: viewModel.albumArtwork,
                fallbackImage: viewModel.appIconImage(),
                size: AudioPlayerTimelineView.Constants.albumArtSize,
                cornerRadius: AudioPlayerTimelineView.Constants.albumArtCornerRadius
            )
            .blur(radius: viewModel.isScrubberShown ? AudioPlayerTimelineView.Constants.blurRadius : 0, opaque: false)
            .opacity(viewModel.isScrubberShown ? AudioPlayerTimelineView.Constants.hoverOpacity : 1)

            if viewModel.isVolumeSliderVisible {
                // The volume button was tapped: the slider takes the place of the title and the
                // subtitle, next to the artwork.
                VolumeSlider(volume: $audioPlayerModel.volume)
                    .tint(.primary)
                    .padding(.horizontal, 8)
                    .transition(.opacity)
            } else {
                SongInfoView(
                    title: currentItem?.title ?? String(localized: "Not Playing", bundle: .module),
                    artist: currentItem?.subtitle ?? "---"
                )
                .blur(radius: viewModel.isScrubberShown ? AudioPlayerTimelineView.Constants.blurRadius : 0, opaque: false)
                .opacity(viewModel.isScrubberShown ? AudioPlayerTimelineView.Constants.hoverOpacity : 1)
            }
        }
        .frame(height: AudioPlayerTimelineView.Constants.contentHeight, alignment: .center)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AudioPlayerTimelineProgressOverlayView: View {
    let audioPlayerModel: AudioPlayerModel
    let viewModel: AudioPlayerBarViewModel

    @ViewBuilder
    var body: some View {
#if os(visionOS)
        // The player's own scrubber row shows the position.
        EmptyView()
#else
        if !viewModel.isScrubberShown && !viewModel.isVolumeSliderVisible {
            ProgressView(
                value: audioPlayerModel.playerTime.elapsedSeconds.isFinite ? audioPlayerModel.playerTime.elapsedSeconds : 0,
                total: audioPlayerModel.playerTime.totalDuration.isFinite ? max(audioPlayerModel.playerTime.totalDuration, 1) : 1
            )
            .progressViewStyle(.linear)
            .tint(.primary.opacity(0.7))
            .scaleEffect(y: AudioPlayerTimelineView.Constants.progressBarScale)
            .offset(y: 8)
            .allowsHitTesting(false)
            .transition(.opacity)
        }
#endif
    }
}

private struct AudioPlayerTimelineScrubberOverlayView: View {
    let audioPlayerModel: AudioPlayerModel
    let viewModel: AudioPlayerBarViewModel
    let hideScrubber: () -> Void

    @Environment(AudioRootModel.self) private var root
    @Environment(\.networkActions) private var networkActions
    @Environment(AppGameStateModel.self) private var appGameStateModel

    @ViewBuilder
    var body: some View {
        if viewModel.isScrubberShown {
            AudioPlayerScrubberView(
                currentTime: audioPlayerModel.playerTime.elapsedSeconds,
                totalDuration: audioPlayerModel.playerTime.totalDuration,
                elapsedText: audioPlayerModel.playerTime.elapsedText,
                onSeek: { position in
                    root.seek(to: position, isGameRunning: appGameStateModel.isGameRunning, networkActions: networkActions)
                }
            )
            .padding(.horizontal, AudioPlayerTimelineView.Constants.horizontalSpacing)
            .padding(.vertical, 8)
            .background {
                AudioPlayerTimelineScrubberBackgroundView(hideScrubber: hideScrubber)
            }
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
            .accessibilityAction(named: Text("Hide Playback Controls", bundle: .module)) {
                hideScrubber()
            }
        }
    }
}

private struct AudioPlayerTimelineScrubberBackgroundView: View {
    let hideScrubber: () -> Void

    var body: some View {
        Button(action: hideScrubber) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.ultraThinMaterial.opacity(0.95))
                .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityHidden(true)
#if os(iOS)
        .contentShape(.rect)
#endif
    }
}

#if os(visionOS)
/// The position of the song as a row of its own: elapsed time, a slider to move forward or
/// backward, and the total time. Sought on release, and shared with the game when one runs.
struct AudioPlayerPersistentScrubberView: View {
    let audioPlayerModel: AudioPlayerModel

    @Environment(AudioRootModel.self) private var root
    @Environment(\.networkActions) private var networkActions
    @Environment(AppGameStateModel.self) private var appGameStateModel

    var body: some View {
        AudioPlayerScrubberView(
            currentTime: audioPlayerModel.playerTime.elapsedSeconds,
            totalDuration: audioPlayerModel.playerTime.totalDuration,
            elapsedText: audioPlayerModel.playerTime.elapsedText,
            onSeek: { position in
                root.seek(to: position, isGameRunning: appGameStateModel.isGameRunning, networkActions: networkActions)
            }
        )
    }
}
#endif
