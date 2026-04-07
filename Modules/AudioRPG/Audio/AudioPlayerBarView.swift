// @copyright André Trettin

import AVFoundation
import CoreRPG
import SwiftUI

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

struct AudioPlayerBarView: View {
    @Environment(AudioRootModel.self) private var root
    
#if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
#endif
    
    @State private var isHovering = false
    @State private var isHoveringVolume = false
    @State private var previousVolume: Double = 0.25
    @State private var albumArtwork: Image?
    @State private var artworkLoadTask: Task<Void, Never>?
    
    // MARK: - Constants
    
    private enum Layout {
        static let albumArtSize: CGFloat = 44
        static let albumArtCornerRadius: CGFloat = 4
        static let contentHeight: CGFloat = 44
        static let horizontalSpacing: CGFloat = 4
        static let progressBarScale: CGFloat = 0.4
        static let blurRadius: CGFloat = 8
        static let hoverOpacity: CGFloat = 0.3
    }
    
    private enum Animation {
        static let hoverSpring = SwiftUI.Animation.spring(response: 0.25, dampingFraction: 0.8)
        static let volumeSpring = SwiftUI.Animation.spring(response: 0.25, dampingFraction: 0.75)
        static let muteSpring = SwiftUI.Animation.spring(response: 0.3, dampingFraction: 0.7)
    }
    
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
        HStack(alignment: .center, spacing: 8) {
            playbackControls
                .padding(.horizontal, 8)

            musicArtTitleTimeline
                .frame(maxWidth: .infinity, alignment: .leading)

            volumeControl
                .padding(.horizontal, 8)
        }
        .padding(.vertical, 8)
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
#if os(iOS)
        // iPad: Always show scrubber (touch-first design)
        if horizontalSizeClass != .compact {
            iPadMusicArtTitleTimeline
        } else {
            // Should not reach here as compact uses AudioPlayerMiniBarView
            EmptyView()
        }
#else
        // macOS: Hover-based scrubber
        macMusicArtTitleTimeline
#endif
    }

    @ViewBuilder
    var iPadMusicArtTitleTimeline: some View {
        // Base content layer (album art + song info)
        HStack(spacing: Layout.horizontalSpacing) {
            // Album art
            albumArtView
                .blur(radius: isHovering ? Layout.blurRadius : 0, opaque: false)

            // Song Info
            songInfoView
                .blur(radius: isHovering ? Layout.blurRadius : 0, opaque: false)
        }
        .frame(height: Layout.contentHeight, alignment: .center)
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(isHovering ? Layout.hoverOpacity : 1)
        .contentShape(Rectangle())
        .onTapGesture {
            // Tap artwork/title to reveal scrubber
            withAnimation(Animation.hoverSpring) {
                isHovering = true
            }
        }
        .overlay(alignment: .bottom) {
            // Progress bar (visible when scrubber hidden)
            if !isHovering {
                progressBarView
                    .offset(y: 8)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .overlay {
            // Scrubber (visible when tapped)
            if isHovering {
                scrubberView
                    .padding(.horizontal, Layout.horizontalSpacing)
                    .padding(.vertical, 8)
                    .background {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(.ultraThinMaterial.opacity(0.95))
                            .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 2)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                // Tap outside (on background) to dismiss
                                withAnimation(Animation.hoverSpring) {
                                    isHovering = false
                                }
                            }
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .onChange(of: currentItem?.id) { _, _ in
            loadAlbumArtwork()
        }
        .onAppear {
            loadAlbumArtwork()
        }
    }

    @ViewBuilder
    var macMusicArtTitleTimeline: some View {
        // Base content layer (album art + song info)
        HStack(spacing: Layout.horizontalSpacing) {
            // Album art
            albumArtView
                .blur(radius: isHovering ? Layout.blurRadius : 0, opaque: false)

            // Song Info
            songInfoView
                .blur(radius: isHovering ? Layout.blurRadius : 0, opaque: false)
        }
        .frame(height: Layout.contentHeight, alignment: .center)
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(isHovering ? Layout.hoverOpacity : 1)
        .allowsHitTesting(!isHovering)
        .overlay(alignment: .bottom) {
            // Progress bar (visible when not hovering)
            if !isHovering {
                progressBarView
                    .offset(y: 8)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .overlay {
            // Scrubber overlay (visible when hovering)
            if isHovering {
                scrubberView
                    .padding(.horizontal, Layout.horizontalSpacing)
                    .padding(.vertical, 8)
                    .background {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(.ultraThinMaterial.opacity(0.95))
                            .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 2)
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(Animation.hoverSpring) {
                isHovering = hovering
            }
        }
        .onChange(of: currentItem?.id) { _, _ in
            loadAlbumArtwork()
        }
        .onAppear {
            loadAlbumArtwork()
        }
    }

    var albumArtView: some View {
        Group {
            if let albumArtwork {
                albumArtwork
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                appIconImage
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
        }
        .frame(width: Layout.albumArtSize, height: Layout.albumArtSize)
        .clipShape(RoundedRectangle(cornerRadius: Layout.albumArtCornerRadius, style: .continuous))
        .shadow(radius: 2, y: 1)
        .accessibilityLabel(Text("Album Artwork", bundle: .module))
        .accessibilityHidden(true) // Decorative image
    }
    
    var songInfoView: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(currentItem?.title ?? String(localized: "Not Playing", bundle: .module).localizedString)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
            Text(currentItem?.artist ?? "---")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    var scrubberView: some View {
        HStack(spacing: 8) {
            Text(root.audioPlayerModel.playerTime.elapsedText)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.primary)
                .monospacedDigit()
                .frame(minWidth: 38)
                .accessibilityLabel(Text("Elapsed Time", bundle: .module))

#if !os(tvOS)
            Slider(value: Binding(
                get: { root.audioPlayerModel.currentTime },
                set: { newValue in
                    root.audioController.skip(to: newValue)
                }
            ), in: 0...max(root.audioPlayerModel.playerTime.totalDuration, 1))
            .tint(.primary)
            .accessibilityLabel(Text("Playback Position", bundle: .module))
            .accessibilityValue(Text("\(formatAccessibilityTime(root.audioPlayerModel.currentTime)) seconds of \(formatAccessibilityTime(root.audioPlayerModel.playerTime.totalDuration)) seconds", bundle: .module))
#endif
            
            Text(formatTotalTime(root.audioPlayerModel.playerTime.totalDuration))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.primary)
                .monospacedDigit()
                .frame(minWidth: 38)
                .accessibilityLabel(Text("Total Duration", bundle: .module))
        }
    }
    
    var progressBarView: some View {
        ProgressView(value: root.audioPlayerModel.currentTime, total: max(root.audioPlayerModel.playerTime.totalDuration, 1))
            .progressViewStyle(.linear)
            .tint(.primary.opacity(0.7))
            .scaleEffect(y: Layout.progressBarScale)
    }
    
    var appIconImage: Image {
#if canImport(AppKit)
        if let appIcon = NSApplication.shared.applicationIconImage {
            return Image(nsImage: appIcon)
        }
#elseif canImport(UIKit)
        if let icons = Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any],
           let primaryIcon = icons["CFBundlePrimaryIcon"] as? [String: Any],
           let iconFiles = primaryIcon["CFBundleIconFiles"] as? [String],
           let iconName = iconFiles.last,
           let uiImage = UIImage(named: iconName) {
            return Image(uiImage: uiImage)
        }
#endif
        // Fallback to system music note
        return Image(systemName: "music.note")
    }
    
    @ViewBuilder var volumeControl: some View {
        @Bindable var audioPlayerModel = root.audioPlayerModel

        HStack(spacing: 0) {
#if !os(tvOS)
            // Volume slider (visible when hovering)
            if isHoveringVolume {
                Slider(value: $audioPlayerModel.volume, in: 0...1)
                .frame(width: 100)
                .tint(.primary)
                .padding(.leading, 12)
                .padding(.trailing, 4)
                .transition(.opacity)
            }
#endif

            // Volume button
            Button {
#if os(macOS)
                // macOS: toggle mute if already hovering, otherwise show slider
                if isHoveringVolume {
                    toggleMute()
                } else {
                    withAnimation(Animation.volumeSpring) {
                        isHoveringVolume = true
                    }
                }
#else
                // iOS/visionOS: first tap shows slider, second tap mutes
                if isHoveringVolume {
                    toggleMute()
                } else {
                    withAnimation(Animation.volumeSpring) {
                        isHoveringVolume = true
                    }
                }
#endif
            } label: {
                Image(systemName: volumeIcon)
                    .font(.body)
                    .frame(width: 32, height: 32)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(root.audioPlayerModel.isMuted ? "Unmute" : "Mute", bundle: .module))
            .accessibilityValue(Text("\(formatAccessibilityTime(root.audioPlayerModel.volume * 100)) percent", bundle: .module))
            .padding(.horizontal, 8)
        }
        .padding(.vertical, 6)
        .frame(height: 44)
        .background {
            Capsule()
                .fill(.ultraThinMaterial.opacity(0.8))
                .background {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    .white.opacity(0.12),
                                    .white.opacity(0.05)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .glassEffect(.regular.tint(.white.opacity(0.03)).interactive())
                }
                .overlay {
                    Capsule()
                        .strokeBorder(.white.opacity(0.15), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 2)
        }
        .contentShape(Rectangle())
#if os(macOS)
        // macOS: use hover behavior
        .onHover { hovering in
            if !hovering && isHoveringVolume {
                withAnimation(Animation.volumeSpring) {
                    isHoveringVolume = false
                }
            }
        }
#else
        // iOS/visionOS: use tap-outside-to-dismiss
        .onTapGesture {
            // Tapping the background (outside button/slider) dismisses
            if isHoveringVolume {
                withAnimation(Animation.volumeSpring) {
                    isHoveringVolume = false
                }
            }
        }
#endif
    }
    
    var volumeIcon: String {
        if root.audioPlayerModel.isMuted || root.audioPlayerModel.volume == 0 {
            return "speaker.slash.fill"
        } else if root.audioPlayerModel.volume < 0.33 {
            return "speaker.wave.1.fill"
        } else if root.audioPlayerModel.volume < 0.66 {
            return "speaker.wave.2.fill"
        } else {
            return "speaker.wave.3.fill"
        }
    }
    
    func toggleMute() {
        withAnimation(Animation.muteSpring) {
            if root.audioPlayerModel.isMuted {
                root.audioPlayerModel.volume = previousVolume
            } else {
                previousVolume = root.audioPlayerModel.volume
                root.audioPlayerModel.volume = 0
            }
        }
    }
    
    var currentItem: PlaylistItem? {
        root.audioPlayerModel.currentItem
    }
    
    func loadAlbumArtwork() {
        // Cancel any existing load task
        artworkLoadTask?.cancel()
        
        guard let currentItem else {
            albumArtwork = nil
            return
        }
        
        artworkLoadTask = Task {
            do {
                let asset = AVURLAsset(url: currentItem.url)
                
                // Check for cancellation
                guard !Task.isCancelled else { return }
                
                let metadata = try await asset.load(.commonMetadata)
                
                // Check for cancellation after async work
                guard !Task.isCancelled else { return }
                
                // Look for artwork in metadata
                for item in metadata {
                    guard let key = item.commonKey?.rawValue,
                          key == AVMetadataKey.commonKeyArtwork.rawValue else {
                        continue
                    }
                    
                    if let data = try await item.load(.dataValue) {
                        guard !Task.isCancelled else { return }
                        
#if canImport(AppKit)
                        if let nsImage = NSImage(data: data) {
                            await MainActor.run {
                                guard !Task.isCancelled else { return }
                                self.albumArtwork = Image(nsImage: nsImage)
                            }
                            return
                        }
#elseif canImport(UIKit)
                        if let uiImage = UIImage(data: data) {
                            await MainActor.run {
                                guard !Task.isCancelled else { return }
                                self.albumArtwork = Image(uiImage: uiImage)
                            }
                            return
                        }
#endif
                    }
                }
                
                // No artwork found in metadata
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    self.albumArtwork = nil
                }
            } catch {
                // Only update if not cancelled
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.albumArtwork = nil
                }
            }
        }
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

    func formatAccessibilityTime(_ time: Double) -> String {
        guard !time.isNaN && time.isFinite else { return "0" }
        return "\(Int(time.rounded()))"
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
