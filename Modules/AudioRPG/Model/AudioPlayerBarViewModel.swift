// @copyright André Trettin

import AVFoundation
import CoreRPG
import ImageIO
import SwiftUI

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// Shared state and logic for AudioPlayerBarView
@MainActor
@Observable
final class AudioPlayerBarViewModel {
    var isScrubberVisible = false
    var isVolumeSliderVisible = false
    var albumArtwork: Image?

    private var artworkLoadTask: Task<Void, Never>?

    /// Cancels an in-flight artwork load without starting a new one — call from
    /// `onDisappear` so a track that's no longer visible doesn't keep loading
    /// artwork in the background. See CODE_AUDIT_Audio §3.7.
    func cancelArtworkLoad() {
        artworkLoadTask?.cancel()
    }

    func loadAlbumArtwork(for item: PlaylistItem?) {
        // Cancel any existing load task
        artworkLoadTask?.cancel()

        guard let item else {
            albumArtwork = nil
            return
        }

        artworkLoadTask = Task { [weak self] in
            let data = await Self.loadArtworkData(url: item.url)
            guard !Task.isCancelled else { return }
            self?.albumArtwork = Self.artworkImage(from: data)
        }
    }

    /// Metadata parsing and data extraction have no UI dependency — @concurrent keeps
    /// them off the main actor (nonisolated async would inherit the caller's isolation).
    @concurrent
    private static func loadArtworkData(url: URL) async -> Data? {
        do {
            let asset = AVURLAsset(url: url)
            let metadata = try await asset.load(.commonMetadata)

            for metadataItem in metadata {
                guard !Task.isCancelled else { return nil }
                guard metadataItem.commonKey?.rawValue == AVMetadataKey.commonKeyArtwork.rawValue else { continue }
                if let data = try await metadataItem.load(.dataValue) {
                    return data
                }
            }
        } catch {
            // No artwork on error — the caller falls back to nil.
        }
        return nil
    }

    /// Longest edge, in pixels, the player bar keeps of the artwork it shows.
    private static let maximumArtworkPixelSize: CGFloat = 1024

    /// Embedded artwork can be several thousand pixels wide while the bar shows a thumbnail, so
    /// it is decoded downsampled, and not at all when its header names more than the pixel
    /// limits. See CODE_AUDIT §8.3.
    static func artworkImage(from data: Data?) -> Image? {
        guard let data,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = ImageDownsampler.downsampledImage(from: source, maxPixelSize: maximumArtworkPixelSize) else { return nil }
        return Image(decorative: image, scale: 1)
    }

    func toggleMute(audioPlayerModel: AudioPlayerModel) {
        // The volume before the mute lives on the player model (kept by `volume` itself), shared
        // by every bar and by a slider dragged to zero.
        audioPlayerModel.volume = audioPlayerModel.isMuted ? audioPlayerModel.previousVolume : 0
    }

    func appIconImage() -> Image {
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
}
