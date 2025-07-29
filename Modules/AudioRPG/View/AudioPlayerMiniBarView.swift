// @copyright André Trettin

import SwiftUI

public struct AudioPlayerMiniBarView: View {
    public init() {
    }
    
    // Mocked state for preview/demo
    @State private var isPlaying = false
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
        HStack(spacing: 24) {
            Button {
                isPlaying.toggle()
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.title2)
                    .padding(8)
                    .background(.regularMaterial, in: Circle())
            }
            
            if tabViewBottomAccessoryPlacement != .inline {
                Button {
                    // Next action
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.title3)
                }
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }
    
    @ViewBuilder
    var musicArtTitleTimeline: some View {
        HStack {
            if tabViewBottomAccessoryPlacement != .inline {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Image(systemName: "music.note")
                            .foregroundStyle(.secondary)
                    )
                    .shadow(radius: 2, y: 1)
            }
            // Song Info
            VStack(alignment: .leading, spacing: 2) {
                Text("Song Title")
                    .font(.headline).bold()
                Text("Artist Name")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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
