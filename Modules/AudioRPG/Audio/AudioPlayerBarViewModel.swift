// @copyright André Trettin

import AVFoundation
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
    var previousVolume: Double = 0.25
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

    private static func artworkImage(from data: Data?) -> Image? {
        guard let data else { return nil }
#if canImport(AppKit)
        if let nsImage = NSImage(data: data) {
            return Image(nsImage: nsImage)
        }
#elseif canImport(UIKit)
        if let uiImage = UIImage(data: data) {
            return Image(uiImage: uiImage)
        }
#endif
        return nil
    }

    func toggleMute(audioPlayerModel: AudioPlayerModel) {
        if audioPlayerModel.isMuted {
            audioPlayerModel.volume = previousVolume
        } else {
            previousVolume = audioPlayerModel.volume
            audioPlayerModel.volume = 0
        }
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
