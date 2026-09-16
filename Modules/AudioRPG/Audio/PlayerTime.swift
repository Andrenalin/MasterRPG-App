// @copyright André Trettin

import AVFoundation
import Foundation

enum TimeConstant {
    static let secsPerMin = 60
    static let secsPerHour = TimeConstant.secsPerMin * 60
}

struct PlayerTime: Equatable, Hashable, Sendable {
    let elapsedText: String
    let remainingText: String
    let totalDuration: Double
    
    static let zero: PlayerTime = .init(elapsedTime: 0, remainingTime: 0)

    init(elapsedTime: Double, remainingTime: Double) {
        elapsedText = PlayerTime.formatted(time: elapsedTime)
        remainingText = PlayerTime.formatted(time: remainingTime)
        totalDuration = elapsedTime + remainingTime
    }

    static func formatted(time: Double) -> String {
        guard time.isFinite else { return "--:--" }
        let totalSeconds = Int(ceil(max(time, 0)))
        let pattern: Duration.TimeFormatStyle.Pattern = totalSeconds >= TimeConstant.secsPerHour
            ? .hourMinuteSecond(padHourToLength: 2)
            : .minuteSecond(padMinuteToLength: 2)
        return Duration.seconds(totalSeconds).formatted(.time(pattern: pattern))
    }
}

struct PlaylistItem: Equatable, Hashable, Identifiable, Sendable {
    /// Fallback artist name for tracks with no item description to use instead.
    static let defaultArtistName = "MasterRPG"

    let id: UUID
    let url: URL
    let title: String
    let artist: String
    let duration: CMTime

    init(id: UUID, url: URL, title: String, artist: String, duration: CMTime) {
        self.id = id
        self.url = url
        self.title = title
        self.artist = artist
        self.duration = duration
    }

    /// Loads `assetUrl`'s duration and builds the resulting item — the "AVURLAsset →
    /// load duration → PlaylistItem" step used by `AudioController`'s asset-loading
    /// path (see CODE_AUDIT §9.17/§7.1).
    static func loading(id: UUID, title: String, artist: String, from assetUrl: URL) async throws -> PlaylistItem {
        let asset = AVURLAsset(url: assetUrl)
        let duration = try await asset.load(.duration)
        return PlaylistItem(id: id, url: asset.url, title: title, artist: artist, duration: duration)
    }
}
