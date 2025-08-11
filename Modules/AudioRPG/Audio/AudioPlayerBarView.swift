// @copyright André Trettin

import CoreRPG
import SwiftUI

struct AudioPlayerBarView: View {
    @Environment(AudioRootModel.self) private var root
            
    var body: some View {
        GlassEffectContainerView {
            HStack(spacing: 16) {
                playbackControls
                
                Spacer(minLength: 8)
                
                musicArtTitleTimeline
                
                Spacer(minLength: 8)
                
                volumeControl
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
#if !os(visionOS)
            .glassEffect(.clear)
#endif

        }
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
            }
#if !os(visionOS)
            .glassEffect(.regular.interactive())
#endif
            .disabled(!root.audioPlayerModel.hasNext)
        }
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
#if !os(visionOS)
        .glassEffect(.regular)
#endif
    }
    
    var volumeControl: some View {
        Button {
            // Next action
        } label: {
            Image(systemName: "speaker.wave.2.fill")
                .font(.title3)
        }
#if !os(visionOS)
        .glassEffect(.regular.interactive())
#endif
    }
    
    var currentItem: PlaylistItem? {
        root.audioPlayerModel.currentItem
    }
}


#Preview(traits: .mockData) {
    ZStack {
        // Simulate window background
        LinearGradient(gradient: Gradient(colors: [.blue.opacity(0.13), .purple.opacity(0.13)]), startPoint: .topLeading, endPoint: .bottomTrailing)
            .ignoresSafeArea()
        AudioPlayerBarView()
            .padding()
    }
}
