// @copyright André Trettin

#if os(iOS)

import AppIntents
import Foundation

/// The action of the "Next Turn" control in Control Center, which lives in the widget extension.
/// The battle runs in the app, so the intent must run there: a `LiveActivityIntent` always runs in
/// the app's process, and on the 27 releases `allowedExecutionTargets` says so explicitly. It is
/// declared here because both the app and the widget extension link CoreRPG; the app's
/// `NextTurnIntent` (GameRPG) is the discoverable one. See CODE_AUDIT_AppIntents3 §4.8.
public struct NextTurnControlIntent: LiveActivityIntent {
    public static let title: LocalizedStringResource = "Next Turn"
    public static let isDiscoverable = false

    @available(iOS 27, *)
    public static var allowedExecutionTargets: IntentExecutionTargets { .main }

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult {
        IntentGameContext.nextTurn()
        return .result()
    }
}

#endif
