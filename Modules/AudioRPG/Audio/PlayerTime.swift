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

    private static func formatted(time: Double) -> String {
        guard time.isFinite else { return "--:--" }
        let totalSeconds = Int(ceil(max(time, 0)))
        let pattern: Duration.TimeFormatStyle.Pattern = totalSeconds >= TimeConstant.secsPerHour
            ? .hourMinuteSecond(padHourToLength: 2)
            : .minuteSecond(padMinuteToLength: 2)
        return Duration.seconds(totalSeconds).formatted(.time(pattern: pattern))
    }
}

struct PlaylistItem: Equatable, Hashable, Identifiable, Sendable {
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
}
