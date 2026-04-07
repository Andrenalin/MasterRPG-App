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
    var isScubberVisible = false
    var isVolumeSliderVisible = false
    var previousVolume: Double = 0.25
    var albumArtwork: Image?

    private var artworkLoadTask: Task<Void, Never>?

    func loadAlbumArtwork(for item: PlaylistItem?) {
        // Cancel any existing load task
        artworkLoadTask?.cancel()

        guard let item else {
            albumArtwork = nil
            return
        }

        artworkLoadTask = Task {
            do {
                let asset = AVURLAsset(url: item.url)

                // Check for cancellation
                guard !Task.isCancelled else { return }

                let metadata = try await asset.load(.commonMetadata)

                // Check for cancellation after async work
                guard !Task.isCancelled else { return }

                // Look for artwork in metadata
                for metadataItem in metadata {
                    guard let key = metadataItem.commonKey?.rawValue,
                          key == AVMetadataKey.commonKeyArtwork.rawValue else {
                        continue
                    }

                    if let data = try await metadataItem.load(.dataValue) {
                        guard !Task.isCancelled else { return }

#if canImport(AppKit)
                        if let nsImage = NSImage(data: data) {
                            guard !Task.isCancelled else { return }
                            self.albumArtwork = Image(nsImage: nsImage)
                            return
                        }
#elseif canImport(UIKit)
                        if let uiImage = UIImage(data: data) {
                            guard !Task.isCancelled else { return }
                            self.albumArtwork = Image(uiImage: uiImage)
                            return
                        }
#endif
                    }
                }

                // No artwork found in metadata
                guard !Task.isCancelled else { return }
                self.albumArtwork = nil
            } catch {
                // Only update if not cancelled
                guard !Task.isCancelled else { return }
                self.albumArtwork = nil
            }
        }
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
