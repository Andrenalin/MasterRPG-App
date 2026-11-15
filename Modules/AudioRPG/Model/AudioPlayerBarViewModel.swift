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

    /// Loads the artwork of `item`. Awaited from the view's `.task(id:)`, so the system cancels it
    /// when the track changes or the view goes away: a track that is no longer visible does not
    /// keep loading artwork in the background. See CODE_AUDIT_Audio §3.7, CODE_AUDIT_26 §4.10.
    func loadAlbumArtwork(for item: PlaylistItem?) async {
        guard let item else {
            albumArtwork = nil
            return
        }

        // The artwork is read and downsampled off the main actor; only the `Image` is built here.
        // See CODE_AUDIT_26 §7.58.
        let image = await Self.loadArtworkImage(url: item.url)
        guard !Task.isCancelled else { return }
        albumArtwork = image.map { Image(decorative: $0, scale: 1) }
    }

    /// Metadata parsing, data extraction and decoding have no UI dependency — @concurrent keeps
    /// them off the main actor (nonisolated async would inherit the caller's isolation).
    @concurrent
    private static func loadArtworkImage(url: URL) async -> CGImage? {
        guard let data = await loadArtworkData(url: url), !Task.isCancelled else { return nil }
        return artworkCGImage(from: data)
    }

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
    private nonisolated static let maximumArtworkPixelSize: CGFloat = 1024

    /// Embedded artwork can be several thousand pixels wide while the bar shows a thumbnail, so
    /// it is decoded downsampled, and not at all when its header names more than the pixel
    /// limits. See CODE_AUDIT §8.3.
    static func artworkImage(from data: Data?) -> Image? {
        artworkCGImage(from: data).map { Image(decorative: $0, scale: 1) }
    }

    nonisolated static func artworkCGImage(from data: Data?) -> CGImage? {
        guard let data,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        return ImageDownsampler.downsampledImage(from: source, maxPixelSize: maximumArtworkPixelSize)
    }

    func toggleMute(audioPlayerModel: AudioPlayerModel) {
        // The volume before the mute lives on the player model (kept by `volume` itself), shared
        // by every bar and by a slider dragged to zero.
        audioPlayerModel.volume = audioPlayerModel.isMuted ? audioPlayerModel.previousVolume : 0
    }

    /// The app icon never changes while the app runs; it is looked up once, not on every body
    /// evaluation of the player bars. See CODE_AUDIT_26 §7.59.
    func appIconImage() -> Image {
        Self.cachedAppIcon
    }

    private static let cachedAppIcon: Image = makeAppIconImage()

    private static func makeAppIconImage() -> Image {
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
