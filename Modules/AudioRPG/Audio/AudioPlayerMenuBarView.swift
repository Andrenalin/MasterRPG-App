// @copyright André Trettin

import SwiftUI

public struct AudioPlayerMenuBarView: View {
    public init() {}

    @Environment(AudioRootModel.self) private var root
    @Environment(\.tabViewBottomAccessoryPlacement) private var tabViewBottomAccessoryPlacement

    public var body: some View {
        VStack(spacing: 12) {
            musicArtTitleTimeline

            playbackControls
        }
    }
}

private extension AudioPlayerMenuBarView {
    var playbackControls: some View {
            HStack(spacing: 24) {
                Button {
                    withAnimation { root.audioController.skipToCurrentItem(offsetBy: -1) }
                } label: {
                    Image(systemName: "backward.fill")
                        .font(.title3)
                }
                .disabled(!root.audioPlayerModel.hasPrev)
                
                Button {
                    withAnimation { root.audioController.togglePlay() }
                } label: {
                    Image(systemName: root.audioPlayerModel.isPlaying ? "pause.fill" : "play.fill")
                        .contentTransition(.symbolEffect(.replace.magic(fallback: .replace)))
                        .font(.title2)
                        .padding(8)
                        .background(.regularMaterial, in: Circle())
                }
                .disabled(!root.audioPlayerModel.playList.isEmpty)
                
                Button {
                    withAnimation { root.audioController.skipToCurrentItem(offsetBy: 1) }
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.title3)
                }
                .disabled(!root.audioPlayerModel.hasNext)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
        }
    
    @ViewBuilder
    var musicArtTitleTimeline: some View {
        VStack(spacing: 4) {
            HStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: "music.note")
                            .foregroundStyle(.secondary)
                    )
                    .shadow(radius: 2, y: 1)
                
                // Song Info
                VStack(alignment: .leading, spacing: 2) {
                    Text(currentItem?.title ?? "")
                        .font(.headline).bold()
                    Text(currentItem?.artist ?? "")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }.overlay {
                HStack {
                    Text(root.audioPlayerModel.playerTime.elapsedText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Spacer(minLength: 0)
                    Text(root.audioPlayerModel.playerTime.remainingText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .opacity(0)
            }
                 
            ProgressView(value: root.audioPlayerModel.currentTime, total: root.audioPlayerModel.playerTime.totalDuration)
                .progressViewStyle(.linear)
        }
    }
    
    var currentItem: PlaylistItem? {
        root.audioPlayerModel.currentItem
    }
}

#Preview {
    ZStack {
        // Simulate window background
        LinearGradient(gradient: Gradient(colors: [.blue.opacity(0.13), .purple.opacity(0.13)]), startPoint: .topLeading, endPoint: .bottomTrailing)
            .ignoresSafeArea()
        AudioPlayerMiniBarView()
            .padding()
    }
}
