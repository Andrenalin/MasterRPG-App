// @copyright André Trettin

import SwiftUI

public struct AudioPlayerMiniBarView: View {
    public init() {}

    @Environment(AudioRootModel.self) private var root
    @Environment(\.tabViewBottomAccessoryPlacement) private var tabViewBottomAccessoryPlacement

    public var body: some View {
        HStack(spacing: 8) {
            musicArtTitleTimeline

            Spacer(minLength: 8)

            playbackControls
        }
        .padding(4)
        .padding(.horizontal)
    }
}

private extension AudioPlayerMiniBarView {
    var playbackControls: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation { root.audioController.togglePlay() }
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
                .background(.regularMaterial, in: Circle())
            }
            .accessibilityLabel(root.audioPlayerModel.isPlaying ? Text("Pause", bundle: .module) : Text("Play", bundle: .module))
            .accessibilityHint(root.audioPlayerModel.isPlaying ? Text("Pause playback", bundle: .module) : Text("Resume playback", bundle: .module))
            .disabled(!root.audioPlayerModel.playList.isEmpty)

            if tabViewBottomAccessoryPlacement != .inline {
                Button {
                    withAnimation { root.audioController.skipToCurrentItem(offsetBy: 1) }
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
    
    @ViewBuilder
    var musicArtTitleTimeline: some View {
        HStack {
            if tabViewBottomAccessoryPlacement != .inline {
                Button {
                    withAnimation { root.audioPlayerModel.showPlayerToolBar = false }
                } label: {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 32, height: 32)
                        .overlay(
                            Image(systemName: "music.note")
                                .foregroundStyle(.secondary)
                        )
                        .shadow(radius: 2, y: 1)
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
    
    var currentItem: PlaylistItem? {
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
