// @copyright André Trettin

import SwiftUI

public struct AudioPlayerMiniBarView: View {
    public init() {}

    @Environment(AudioRoot.self) private var root
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
                Image(systemName: root.audioPlayerModel.isPlaying ? "pause.fill" : "play.fill")
                    .contentTransition(.symbolEffect(.replace.magic(fallback: .replace)))
                    .font(.title2)
                    .padding(8)
                    .background(.regularMaterial, in: Circle())
            }
            .disabled(!root.audioPlayerModel.playList.isEmpty)
            
            if tabViewBottomAccessoryPlacement != .inline {
                Button {
                    withAnimation { root.audioController.skipToCurrentItem(offsetBy: 1) }
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.title3)
                }
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
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Image(systemName: "music.note")
                            .foregroundStyle(.secondary)
                    )
                    .shadow(radius: 2, y: 1)
                    .onTapGesture {
                        withAnimation { root.audioPlayerModel.showPlayerToolBar = false }
                    }
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

//#Preview(traits: .mockData) {
//    ZStack {
//        // Simulate window background
//        LinearGradient(gradient: Gradient(colors: [.blue.opacity(0.13), .purple.opacity(0.13)]), startPoint: .topLeading, endPoint: .bottomTrailing)
//            .ignoresSafeArea()
//        AudioPlayerMiniBarView()
//            .padding()
//    }
//}
