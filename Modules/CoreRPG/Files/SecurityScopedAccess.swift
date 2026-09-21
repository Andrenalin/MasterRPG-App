// @copyright André Trettin

import Foundation

/// A started security-scoped resource access that is only stopped again when it was actually
/// started. `startAccessingSecurityScopedResource()` returns `false` for urls that need no scope
/// (an app-container file); stopping one anyway is an unbalanced call that can end an outer
/// scope's access. Sites that wrote `_ = url.start…` followed by an unconditional
/// `defer { url.stop… }` all had that problem. See CODE_AUDIT_15 §9.17.
public struct SecurityScopedAccess: Sendable {
    fileprivate let url: URL
    fileprivate let didStart: Bool

    /// Ends the access if this value started it.
    public func stop() {
        guard didStart else { return }
        url.stopAccessingSecurityScopedResource()
    }
}

public extension URL {
    /// Starts security-scoped access; call `stop()` on the result (typically in a `defer`).
    func startSecurityScopedAccess() -> SecurityScopedAccess {
        SecurityScopedAccess(url: self, didStart: startAccessingSecurityScopedResource())
    }
}
