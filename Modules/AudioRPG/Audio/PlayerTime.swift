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
