// @copyright André Trettin

import Foundation

/// How the download of an item's file is going on this device: kept in memory per item in
/// `ItemGameModel.transfers`, shown by `TransferStatusRow`, never sent to the game master.
public struct ItemTransferStatus: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        /// The download runs; `duration` is how long it has been running.
        case loading
        /// The bytes arrived after `duration`.
        case done
        /// The bytes did not arrive (deadline, error).
        case failed
    }

    public init(state: State, duration: Duration = .zero, byteCount: Int = 0) {
        self.state = state
        self.duration = duration
        self.byteCount = byteCount
    }

    public let state: State
    public let duration: Duration
    public let byteCount: Int

    /// The average rate of a finished download; `nil` while it runs, after a failure and
    /// when nothing was measured.
    public var bytesPerSecond: Int? {
        guard state == .done, byteCount > 0 else { return nil }
        let seconds = duration.seconds
        guard seconds > 0 else { return nil }
        return Int(Double(byteCount) / seconds)
    }

    /// `4.2s · 1.3 MB/s` for a transfer of `byteCount` bytes that took `duration`; only the
    /// time when the rate cannot be told.
    public static func summary(duration: Duration, byteCount: Int) -> String {
        let time = duration.formatted(Self.durationStyle)
        let seconds = duration.seconds
        guard byteCount > 0, seconds > 0 else { return time }
        let rate = Int64(Double(byteCount) / seconds).formatted(.byteCount(style: .file))
        return "\(time) · \(rate)/s"
    }

    public static let durationStyle = Duration.UnitsFormatStyle(
        allowedUnits: [.minutes, .seconds],
        width: .narrow,
        fractionalPart: .show(length: 1)
    )
}

public extension Duration {
    /// The duration in seconds, with the fraction.
    var seconds: Double {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
