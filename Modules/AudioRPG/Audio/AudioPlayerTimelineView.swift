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
#if os(iOS)
        AudioPlayerTimelineIPadView(
            currentItem: currentItem,
            audioPlayerModel: audioPlayerModel,
            viewModel: viewModel,
            showScrubber: showScrubber,
            hideScrubber: hideScrubber
        )
#else
        AudioPlayerTimelineMacView(
            currentItem: currentItem,
            audioPlayerModel: audioPlayerModel,
            viewModel: viewModel,
            hideScrubber: hideScrubber
        )
#endif
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

/// iPad timeline (tap-based): tapping anywhere reveals the scrubber.
private struct AudioPlayerTimelineIPadView: View {
    let currentItem: PlaylistItem?
    let audioPlayerModel: AudioPlayerModel
    let viewModel: AudioPlayerBarViewModel
    let showScrubber: () -> Void
    let hideScrubber: () -> Void

    var body: some View {
        Button {
            showScrubber()
        } label: {
            AudioPlayerTimelineContentLayerView(currentItem: currentItem, viewModel: viewModel)
                .contentShape(.rect)
        }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Show Playback Controls", bundle: .module))
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
            .task(id: currentItem?.id) {
                viewModel.loadAlbumArtwork(for: currentItem)
            }
            .onDisappear {
                viewModel.cancelArtworkLoad()
            }
    }
}

/// macOS timeline (hover-based): hovering reveals the scrubber.
private struct AudioPlayerTimelineMacView: View {
    let currentItem: PlaylistItem?
    let audioPlayerModel: AudioPlayerModel
    let viewModel: AudioPlayerBarViewModel
    let hideScrubber: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        AudioPlayerTimelineContentLayerView(currentItem: currentItem, viewModel: viewModel)
            .allowsHitTesting(!viewModel.isScrubberVisible)
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
            .contentShape(Rectangle())
        #if !os(tvOS)
            .onHover { hovering in
                withAnimation(reduceMotion ? nil : AudioPlayerTimelineView.Constants.hoverSpring) {
                    viewModel.isScrubberVisible = hovering
                }
            }
        #endif
            .task(id: currentItem?.id) {
                viewModel.loadAlbumArtwork(for: currentItem)
            }
            .onDisappear {
                viewModel.cancelArtworkLoad()
            }
    }
}

private struct AudioPlayerTimelineContentLayerView: View {
    let currentItem: PlaylistItem?
    let viewModel: AudioPlayerBarViewModel

    var body: some View {
        HStack(spacing: AudioPlayerTimelineView.Constants.horizontalSpacing) {
            AlbumArtworkView(
                artwork: viewModel.albumArtwork,
                fallbackImage: viewModel.appIconImage(),
                size: AudioPlayerTimelineView.Constants.albumArtSize,
                cornerRadius: AudioPlayerTimelineView.Constants.albumArtCornerRadius
            )
            .blur(radius: viewModel.isScrubberVisible ? AudioPlayerTimelineView.Constants.blurRadius : 0, opaque: false)

            SongInfoView(
                title: currentItem?.title ?? String(localized: "Not Playing", bundle: .module),
                artist: currentItem?.artist ?? "---"
            )
            .blur(radius: viewModel.isScrubberVisible ? AudioPlayerTimelineView.Constants.blurRadius : 0, opaque: false)
        }
        .frame(height: AudioPlayerTimelineView.Constants.contentHeight, alignment: .center)
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(viewModel.isScrubberVisible ? AudioPlayerTimelineView.Constants.hoverOpacity : 1)
    }
}

private struct AudioPlayerTimelineProgressOverlayView: View {
    let audioPlayerModel: AudioPlayerModel
    let viewModel: AudioPlayerBarViewModel

    @ViewBuilder
    var body: some View {
        if !viewModel.isScrubberVisible {
            ProgressView(
                value: audioPlayerModel.currentTime.isFinite ? audioPlayerModel.currentTime : 0,
                total: audioPlayerModel.playerTime.totalDuration.isFinite ? max(audioPlayerModel.playerTime.totalDuration, 1) : 1
            )
            .progressViewStyle(.linear)
            .tint(.primary.opacity(0.7))
            .scaleEffect(y: AudioPlayerTimelineView.Constants.progressBarScale)
            .offset(y: 8)
            .allowsHitTesting(false)
            .transition(.opacity)
        }
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
        if viewModel.isScrubberVisible {
            AudioPlayerScrubberView(
                currentTime: audioPlayerModel.currentTime,
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
