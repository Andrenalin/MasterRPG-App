// @copyright André Trettin

import CoreRPG
import SwiftUI

public struct AudioPlayerMiniBarView: View {
    public init(showsMetadata: Bool = true) {
        self.showsMetadata = showsMetadata
    }

    let showsMetadata: Bool

    @Environment(AudioRootModel.self) private var root
    @Environment(\.tabViewBottomAccessoryPlacement) private var tabViewBottomAccessoryPlacement

    // Reuses the same artwork-loading model as the full player bar instead of
    // always showing a static placeholder. See CODE_AUDIT_Audio §8.3.
    @State private var viewModel = AudioPlayerBarViewModel()

    public var body: some View {
        HStack(spacing: 8) {
            if showsMetadata {
                AudioPlayerMiniBarMusicArtTitleTimelineView(viewModel: viewModel)

                Spacer(minLength: 8)
            }

            AudioPlayerMiniBarPlaybackControlsView()
        }
        .padding(4)
        .padding(.horizontal)
        .frame(maxWidth: showsMetadata ? .infinity : nil)
        .task(id: root.audioPlayerModel.currentItem?.id) {
            viewModel.loadAlbumArtwork(for: root.audioPlayerModel.currentItem)
        }
        .onDisappear {
            viewModel.cancelArtworkLoad()
        }
    }
}

// MARK: - Extracted subviews (CODE_AUDIT §8.3)

private struct AudioPlayerMiniBarPlaybackControlsView: View {
    @Environment(AudioRootModel.self) private var root
    @Environment(\.tabViewBottomAccessoryPlacement) private var tabViewBottomAccessoryPlacement
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(.default.reduced(if: reduceMotion)) { root.audioController.togglePlay() }
            } label: {
                Label {
                    Text(root.audioPlayerModel.isPlaying ? "Pause" : "Play", bundle: .module)
                } icon: {
                    Image(systemName: root.audioPlayerModel.isPlaying ? "pause.fill" : "play.fill")
                }
                .labelStyle(.iconOnly)
                .contentTransition(.symbolEffect(.replace.magic(fallback: .replace)))
                .font(.title2)
                .padding(8)
                .background(.regularMaterial, in: .circle)
            }
            .accessibilityLabel(root.audioPlayerModel.isPlaying ? Text("Pause", bundle: .module) : Text("Play", bundle: .module))
            .accessibilityHint(root.audioPlayerModel.isPlaying ? Text("Pause playback", bundle: .module) : Text("Resume playback", bundle: .module))
            .disabled(root.audioPlayerModel.playList.isEmpty)

            if tabViewBottomAccessoryPlacement != .inline {
                Button {
                    withAnimation(.default.reduced(if: reduceMotion)) { root.audioController.skipToCurrentItem(offsetBy: 1) }
                } label: {
                    Label {
                        Text("Next", bundle: .module)
                    } icon: {
                        Image(systemName: "forward.fill")
                    }
                    .labelStyle(.iconOnly)
                    .font(.title3)
                }
                .accessibilityLabel(Text("Next Track", bundle: .module))
                .accessibilityHint(Text("Play the next track in the playlist", bundle: .module))
                .disabled(!root.audioPlayerModel.hasNext)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }
}

private struct AudioPlayerMiniBarMusicArtTitleTimelineView: View {
    let viewModel: AudioPlayerBarViewModel

    @Environment(AudioRootModel.self) private var root
    @Environment(\.tabViewBottomAccessoryPlacement) private var tabViewBottomAccessoryPlacement
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder
    var body: some View {
        HStack {
            if tabViewBottomAccessoryPlacement != .inline {
                Button {
                    withAnimation(.default.reduced(if: reduceMotion)) { root.audioPlayerModel.showPlayerToolBar = false }
                } label: {
                    AlbumArtworkView(
                        artwork: viewModel.albumArtwork,
                        fallbackImage: viewModel.appIconImage(),
                        size: 32,
                        cornerRadius: 6
                    )
                }
                .accessibilityLabel(Text("Now Playing", bundle: .module))
                .accessibilityHint(Text("Hide player toolbar", bundle: .module))
                .buttonStyle(.plain)
            }
            // Song Info
            VStack(alignment: .leading, spacing: 2) {
                Text(currentItem?.title ?? "")
                    .font(.headline).bold()
                    .lineLimit(1)

                Text(currentItem?.artist ?? "")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var currentItem: PlaylistItem? {
        root.audioPlayerModel.currentItem
    }
}

#Preview(traits: .mockData) {
    ZStack {
        LinearGradient(
            colors: [.blue.opacity(0.13), .purple.opacity(0.13)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()

        AudioPlayerMiniBarView()
            .padding()
    }
}
