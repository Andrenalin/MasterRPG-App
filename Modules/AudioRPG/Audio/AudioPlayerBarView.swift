// @copyright André Trettin

import SwiftUI

struct AudioPlayerBarView: View {
    @Environment(AudioRootModel.self) private var root
            
    var body: some View {
        HStack(spacing: 16) {
            playbackControls

            Spacer(minLength: 8)

            musicArtTitleTimeline
            
            Spacer(minLength: 8)
                        
            volumeControl
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.13), lineWidth: 0.6)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 24, y: 4)
    }
}

private extension AudioPlayerBarView {
    var playbackControls: some View {
        HStack(spacing: 24) {
            Button {
                withAnimation { root.audioController.skipToCurrentItem(offsetBy: -1) }
            } label: {
                Image(systemName: "backward.fill")
                    .font(.title3)
                    .padding(8)
                    .background(.regularMaterial, in: Circle())
            }
#if !os(visionOS)
            .glassEffect(.regular.interactive())
#endif
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
#if !os(visionOS)
            .glassEffect(.regular.interactive())
#endif
            .disabled(root.audioPlayerModel.playList.isEmpty)
            
            Button {
                withAnimation { root.audioController.skipToCurrentItem(offsetBy: 1) }
            } label: {
                Image(systemName: "forward.fill")
                    .font(.title3)
                    .padding(8)
                    .background(.regularMaterial, in: Circle())
            }
#if !os(visionOS)
            .glassEffect(.regular.interactive())
#endif
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
    
    var volumeControl: some View {
        Button {
            // Next action
        } label: {
            Image(systemName: "speaker.wave.2.fill")
                .font(.title3)
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
        AudioPlayerBarView()
            .padding()
    }
}
