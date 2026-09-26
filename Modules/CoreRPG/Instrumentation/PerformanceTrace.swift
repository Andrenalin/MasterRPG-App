// @copyright André Trettin

import Foundation
import os

/// Instruments markers for expensive user actions and asynchronous pipelines.
///
/// The signposter uses the Points of Interest category so intervals appear in
/// Instruments alongside SwiftUI, Swift Tasks, CPU, and hang diagnostics.
/// `OSSignposter.isEnabled` keeps the disabled-path overhead intentionally small.
public enum PerformanceTrace {
    public static let subsystem = "de.andretrettin.MasterRPG.performance"

    private static let signposter = OSSignposter(
        subsystem: subsystem,
        category: .pointsOfInterest
    )

    // Checked `Sendable`: `OSSignpostIntervalState` is `Sendable` in the SDK and both stored
    // properties are `let`. See CODE_AUDIT_18 §3.18.
    public struct Interval: Sendable {
        fileprivate let name: StaticString
        fileprivate let state: OSSignpostIntervalState

        public func end() {
            PerformanceTrace.signposter.endInterval(name, state)
        }
    }

    public static func event(_ name: StaticString) {
        guard signposter.isEnabled else { return }
        signposter.emitEvent(name)
    }

    public static func event(
        _ name: StaticString,
        source: String,
        count: Int
    ) {
        guard signposter.isEnabled else { return }
        signposter.emitEvent(
            name,
            "source=\(source, privacy: .public) count=\(count)"
        )
    }

    public static func cacheEvent(
        hit: Bool,
        itemId: UUID,
        kind: String,
        source: String
    ) {
        guard signposter.isEnabled else { return }
        let name: StaticString = hit ? "CacheHit" : "CacheMiss"
        signposter.emitEvent(
            name,
            "item=\(itemId.uuidString, privacy: .public) kind=\(kind, privacy: .public) source=\(source, privacy: .public)"
        )
    }

    public static func begin(_ name: StaticString) -> Interval? {
        guard signposter.isEnabled else { return nil }
        let id = signposter.makeSignpostID()
        return Interval(
            name: name,
            state: signposter.beginInterval(name, id: id)
        )
    }

    public static func begin(
        _ name: StaticString,
        itemId: UUID,
        kind: String
    ) -> Interval? {
        guard signposter.isEnabled else { return nil }
        let id = signposter.makeSignpostID()
        let state = signposter.beginInterval(
            name,
            id: id,
            "item=\(itemId.uuidString, privacy: .public) kind=\(kind, privacy: .public)"
        )
        return Interval(name: name, state: state)
    }

    public static func begin(
        _ name: StaticString,
        source: String,
        count: Int
    ) -> Interval? {
        guard signposter.isEnabled else { return nil }
        let id = signposter.makeSignpostID()
        let state = signposter.beginInterval(
            name,
            id: id,
            "source=\(source, privacy: .public) count=\(count)"
        )
        return Interval(name: name, state: state)
    }

    public static func begin(
        _ name: StaticString,
        source: String,
        byteCount: Int
    ) -> Interval? {
        guard signposter.isEnabled else { return nil }
        let id = signposter.makeSignpostID()
        let state = signposter.beginInterval(
            name,
            id: id,
            "source=\(source, privacy: .public) bytes=\(byteCount)"
        )
        return Interval(name: name, state: state)
    }
}
