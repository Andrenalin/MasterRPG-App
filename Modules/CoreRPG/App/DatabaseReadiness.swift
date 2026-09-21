// @copyright André Trettin

import Foundation

/// Lets background App Intents wait until the Core Data stack and the root models exist.
///
/// Intents declared with `.background` can run when the app was launched without a scene, i.e.
/// before the view-driven database setup ran. Without a gate they insert into a root model that
/// has no `dataControllable`, "save" nothing and report success, and entity queries resolve to
/// empty lists. See CODE_AUDIT_16 §5.3.
@MainActor
public enum DatabaseReadiness {
    /// Longest an intent waits before continuing anyway (e.g. an iCloud account alert is pending).
    public static let timeout: Duration = .seconds(20)

    public private(set) static var isReady = false
    private static var starter: (@MainActor () -> Void)?
    private static var waiters: [UUID: CheckedContinuation<Void, Never>] = [:]

    /// Registers the closure that starts database setup when no scene did.
    public static func configure(start: @escaping @MainActor () -> Void) {
        starter = start
    }

    public static func markReady() {
        isReady = true
        resumeAll()
    }

    /// Returns once the database and root models are ready, or after `timeout`.
    public static func wait() async {
        // Without a registered starter (tests, previews) nothing could ever make it ready.
        guard !isReady, let starter else { return }
        starter()
        guard !isReady else { return }
        let id = UUID()
        Task { @MainActor in
            try? await Task.sleep(for: timeout)
            waiters.removeValue(forKey: id)?.resume()
        }
        await withCheckedContinuation { continuation in
            waiters[id] = continuation
        }
    }

    private static func resumeAll() {
        let pending = waiters
        waiters.removeAll()
        pending.values.forEach { $0.resume() }
    }
}
