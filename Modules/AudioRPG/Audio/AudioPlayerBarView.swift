// @copyright André Trettin

import CoreRPG
import SwiftUI

struct AudioPlayerBarView: View {
    @Environment(AudioRootModel.self) private var root
    
#if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
#endif
    
    @State private var isHovering = false
    
    var body: some View {
#if os(iOS)
        if horizontalSizeClass == .compact {
            GlassEffectContainerView {
                AudioPlayerMiniBarView()
                    .glassEffect(.clear)
            }
        } else {
            GlassEffectContainerView {
                content
                    .glassEffect(.clear)
            }
        }
#elseif os(visionOS)
        content
#else
        GlassEffectContainer {
            content
                .glassEffect(.clear)
        }
#endif
    }
    
    var content: some View {
        HStack(spacing: 12) {
            playbackControls
            
            Spacer(minLength: 8)
            
            musicArtTitleTimeline
            
            Spacer(minLength: 8)
            
            volumeControl
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

private extension AudioPlayerBarView {
    var playbackControls: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation { root.audioController.skipToCurrentItem(offsetBy: -1) }
            } label: {
                Image(systemName: "backward.fill")
                    .font(.title3)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Previous Track", bundle: .module))
            .disabled(!root.audioPlayerModel.hasPrev)
            
            Button {
                withAnimation { root.audioController.togglePlay() }
            } label: {
                Image(systemName: root.audioPlayerModel.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title2)
                    .contentTransition(.symbolEffect(.replace.magic(fallback: .replace)))
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(root.audioPlayerModel.isPlaying ? Text("Pause", bundle: .module) : Text("Play", bundle: .module))
            .disabled(root.audioPlayerModel.playList.isEmpty)
            
            Button {
                withAnimation { root.audioController.skipToCurrentItem(offsetBy: 1) }
            } label: {
                Image(systemName: "forward.fill")
                    .font(.title3)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Next Track", bundle: .module))
            .disabled(!root.audioPlayerModel.hasNext)
        }
        .foregroundStyle(.primary)
    }
    
    @ViewBuilder
    var musicArtTitleTimeline: some View {
        VStack(spacing: 4) {
            HStack(spacing: 10) {
                // Album art
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(.secondary.opacity(0.15))
                    .frame(width: 48, height: 48)
                    .overlay(
                        Image(systemName: "music.note")
                            .foregroundStyle(.secondary)
                            .font(.body)
                    )
                
                // Song Info
                VStack(alignment: .leading, spacing: 1) {
                    Text(currentItem?.title ?? "Not Playing")
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text(currentItem?.artist ?? "---")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            // Time scrubber (shows on hover)
            if isHovering {
                HStack(spacing: 6) {
                    Text(root.audioPlayerModel.playerTime.elapsedText)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    
                    ProgressView(value: root.audioPlayerModel.currentTime, total: root.audioPlayerModel.playerTime.totalDuration)
                        .progressViewStyle(.linear)
                        .tint(.primary)
                    
                    Text(formatTotalTime(root.audioPlayerModel.playerTime.totalDuration))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
#if !os(tvOS)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
            }
        }
#endif
    }
    
    var volumeControl: some View {
        Button {
            // Volume action
        } label: {
            Image(systemName: "speaker.wave.2.fill")
                .font(.body)
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Volume Control", bundle: .module))
    }
    
    var currentItem: PlaylistItem? {
        root.audioPlayerModel.currentItem
    }
    
    func formatTotalTime(_ time: Double) -> String {
        guard !time.isNaN else { return "--:--" }
        var seconds = Int(ceil(time))
        var hours = 0
        var mins = 0
        
        if seconds > TimeConstant.secsPerHour {
            hours = seconds / TimeConstant.secsPerHour
            seconds -= hours * TimeConstant.secsPerHour
        }
        
        if seconds > TimeConstant.secsPerMin {
            mins = seconds / TimeConstant.secsPerMin
            seconds -= mins * TimeConstant.secsPerMin
        }
        
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, mins, seconds)
        } else {
            return String(format: "%02d:%02d", mins, seconds)
        }
    }
}


//#Preview(traits: .mockData) {
//    ZStack {
//        // Simulate window background
//        LinearGradient(gradient: Gradient(colors: [.blue.opacity(0.13), .purple.opacity(0.13)]), startPoint: .topLeading, endPoint: .bottomTrailing)
//            .ignoresSafeArea()
//        AudioPlayerBarView()
//            .padding()
//    }
//}
