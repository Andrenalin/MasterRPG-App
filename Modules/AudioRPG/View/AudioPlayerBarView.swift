// @copyright André Trettin

import SwiftUI

struct AudioPlayerBarView: View {
    // Mocked state for preview/demo
    @State private var isPlaying = false
    @State private var progress: Double = 0.4
    @State private var volume: Double = 0.7
    
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
                // Previous action
            } label: {
                Image(systemName: "backward.fill")
                    .font(.title3)
            }
            Button {
                isPlaying.toggle()
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.title2)
                    .padding(8)
                    .background(.regularMaterial, in: Circle())
            }
            Button {
                // Next action
            } label: {
                Image(systemName: "forward.fill")
                    .font(.title3)
            }
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
                    Text("Song Title")
                        .font(.headline).bold()
                    Text("Artist Name")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }.overlay {
                HStack {
                    Text("1:13")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Text("3:25")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .opacity(0)
            }
                 
            ProgressView(value: progress, total: 1.0)
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
