// @copyright André Trettin

import AVFoundation
import Foundation

struct PlaylistItem: Equatable, Hashable, Identifiable, Sendable {
    /// Fallback subtitle for tracks with no item description to use instead (and the artist the lock screen shows).
    static let defaultArtistName = "MasterRPG"

    let id: UUID
    let url: URL
    let title: String
    let subtitle: String
    let duration: CMTime

    init(id: UUID, url: URL, title: String, subtitle: String, duration: CMTime) {
        self.id = id
        self.url = url
        self.title = title
        self.subtitle = subtitle
        self.duration = duration
    }

    /// Loads `assetUrl`'s duration and builds the resulting item — the "AVURLAsset →
    /// load duration → PlaylistItem" step used by `AudioController`'s asset-loading
    /// path (see CODE_AUDIT §9.17/§7.1).
    static func loading(id: UUID, title: String, subtitle: String, from assetUrl: URL) async throws -> PlaylistItem {
        let asset = AVURLAsset(url: assetUrl)
        let duration = try await asset.load(.duration)
        return PlaylistItem(id: id, url: asset.url, title: title, subtitle: subtitle, duration: duration)
    }
}
