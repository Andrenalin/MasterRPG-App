// @copyright André Trettin

import Foundation

/// How often the master answered `.failed` to a player's Character package, for which
/// Character version, and when the next announcement may go out. A rejected package was
/// announced again on every later master message, and exported and uploaded again each time,
/// with no limit. See CODE_AUDIT_21 §5.5 and CODE_AUDIT_Audio2 §9.15.
struct CharacterRejectionPolicy: Sendable {
    /// Rejections of one Character version after which it is no longer sent.
    static let maximumRejections = 3
    /// How often a rejected Character is looked at again for a changed version.
    static let probeInterval: Duration = .seconds(60)

    private(set) var rejections = 0
    private var rejectedVersion: Int?
    private var retryNotBefore: ContinuousClock.Instant?

    /// The delay before the announcement after the `rejections`-th rejection: 5 s, then 20 s.
    static func retryDelay(afterRejection rejections: Int) -> Duration {
        .seconds(5 * (1 << (2 * max(0, rejections - 1))))
    }

    /// Whether a retry delay still runs.
    func isDelayed(now: ContinuousClock.Instant = .now) -> Bool {
        guard let retryNotBefore else { return false }
        return now < retryNotBefore
    }

    /// Records a rejection of `version`. Returns `true` when that was the rejection after
    /// which the Character is no longer sent.
    mutating func record(version: Int, now: ContinuousClock.Instant = .now) -> Bool {
        if rejectedVersion != version {
            rejectedVersion = version
            rejections = 0
        }
        rejections += 1
        guard rejections < Self.maximumRejections else {
            retryNotBefore = now + Self.probeInterval
            return rejections == Self.maximumRejections
        }
        retryNotBefore = now + Self.retryDelay(afterRejection: rejections)
        return false
    }

    /// Whether the Character of `version` may be announced. A version the master rejected
    /// `maximumRejections` times stays unsent; it is looked at again after the probe interval,
    /// because an edited Character has a new version and gets new attempts.
    mutating func mayAnnounce(version: Int, now: ContinuousClock.Instant = .now) -> Bool {
        guard rejections >= Self.maximumRejections else { return true }
        guard rejectedVersion == version else {
            reset()
            return true
        }
        retryNotBefore = now + Self.probeInterval
        return false
    }

    mutating func reset() {
        rejections = 0
        rejectedVersion = nil
        retryNotBefore = nil
    }
}
