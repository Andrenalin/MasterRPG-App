// @copyright André Trettin

import CoreRPG
import SwiftUI

#Preview(traits: .mockData) {
    @Previewable @Environment(AudioRootModel.self) var root
    @Previewable @State var viewModel = AudioPlayerBarViewModel()
    AudioPlayerTimelineView(
        currentItem: root.audioPlayerModel.currentItem,
        audioController: root.audioController,
        audioPlayerModel: root.audioPlayerModel,
        viewModel: viewModel
    )
    .padding()
}

struct AudioPlayerTimelineView: View {
    let currentItem: PlaylistItem?
    let audioController: AudioController
    let audioPlayerModel: AudioPlayerModel
    @Bindable var viewModel: AudioPlayerBarViewModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Constants {
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
        iPadTimelineView
#else
        macTimelineView
#endif
    }

    // MARK: - iPad Timeline (Tap-based)

    @ViewBuilder
    private var iPadTimelineView: some View {
        Button {
            showScrubber()
        } label: {
            contentLayer
                .contentShape(.rect)
        }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Show Playback Controls", bundle: .module))
            .overlay(alignment: .bottom) {
                progressOverlay
            }
            .overlay {
                scrubberOverlay
            }
            .task(id: currentItem?.id) {
                viewModel.loadAlbumArtwork(for: currentItem)
            }
    }

    // MARK: - macOS Timeline (Hover-based)

    @ViewBuilder
    private var macTimelineView: some View {
        contentLayer
            .allowsHitTesting(!viewModel.isScubberVisible)
            .overlay(alignment: .bottom) {
                progressOverlay
            }
            .overlay {
                scrubberOverlay
            }
            .contentShape(Rectangle())
        #if !os(tvOS)
            .onHover { hovering in
                withAnimation(reduceMotion ? nil : Constants.hoverSpring) {
                    viewModel.isScubberVisible = hovering
                }
            }
        #endif
            .task(id: currentItem?.id) {
                viewModel.loadAlbumArtwork(for: currentItem)
            }
    }

    // MARK: - Shared Components

    private var contentLayer: some View {
        HStack(spacing: Constants.horizontalSpacing) {
            AlbumArtworkView(
                artwork: viewModel.albumArtwork,
                fallbackImage: viewModel.appIconImage(),
                size: Constants.albumArtSize,
                cornerRadius: Constants.albumArtCornerRadius
            )
            .blur(radius: viewModel.isScubberVisible ? Constants.blurRadius : 0, opaque: false)

            SongInfoView(
                title: currentItem?.title ?? String(localized: "Not Playing", bundle: .module),
                artist: currentItem?.artist ?? "---"
            )
            .blur(radius: viewModel.isScubberVisible ? Constants.blurRadius : 0, opaque: false)
        }
        .frame(height: Constants.contentHeight, alignment: .center)
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(viewModel.isScubberVisible ? Constants.hoverOpacity : 1)
    }

    @ViewBuilder
    private var progressOverlay: some View {
        if !viewModel.isScubberVisible {
            ProgressView(
                value: audioPlayerModel.currentTime,
                total: max(audioPlayerModel.playerTime.totalDuration, 1)
            )
            .progressViewStyle(.linear)
            .tint(.primary.opacity(0.7))
            .scaleEffect(y: Constants.progressBarScale)
            .offset(y: 8)
            .allowsHitTesting(false)
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private var scrubberOverlay: some View {
        if viewModel.isScubberVisible {
            AudioPlayerScrubberView(
                currentTime: audioPlayerModel.currentTime,
                totalDuration: audioPlayerModel.playerTime.totalDuration,
                elapsedText: audioPlayerModel.playerTime.elapsedText,
                onSeek: { audioController.skip(to: $0) }
            )
            .padding(.horizontal, Constants.horizontalSpacing)
            .padding(.vertical, 8)
            .background {
                scrubberBackground
            }
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
            .accessibilityAction(named: Text("Hide Playback Controls", bundle: .module)) {
                hideScrubber()
            }
        }
    }

    private var scrubberBackground: some View {
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

    private func showScrubber() {
        withAnimation(reduceMotion ? nil : Constants.hoverSpring) {
            viewModel.isScubberVisible = true
        }
    }

    private func hideScrubber() {
        withAnimation(reduceMotion ? nil : Constants.hoverSpring) {
            viewModel.isScubberVisible = false
        }
    }
}
