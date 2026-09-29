// @copyright André Trettin

import Foundation
import Observation

/// App-wide record of persistence failures, observed by the root views' banner.
///
/// `ItemDataModel.lastPersistenceError` is per module and was never read, so every failed
/// save, discarded edit or failed file replacement stayed silent. The center collects them
/// in one place. A save error clears on the next successful save; file errors and discarded
/// edits stay until the user dismisses the banner. See CODE_AUDIT_19 §5.13.
@MainActor @Observable
public final class PersistenceIssueCenter {
    public static let shared = PersistenceIssueCenter()

    /// The latest failed save or flush, `nil` after the next successful save.
    public private(set) var saveError: String?
    /// The latest failed file attach or replacement, kept until dismissed.
    public private(set) var fileError: String?
    /// Edits discarded after repeated save failures since the last dismiss.
    public private(set) var discardedEditCount = 0

    public var hasIssue: Bool {
        saveError != nil || fileError != nil || discardedEditCount > 0
    }

    init() {}

    public func recordSaveError(_ error: any Error) {
        saveError = error.localizedDescription
    }

    /// Call after a `context.save()` succeeded, never after a flush alone: a flush commits
    /// nothing, so it can't prove an earlier failure recovered.
    public func recordSuccessfulSave() {
        saveError = nil
    }

    public func recordFileError(_ error: any Error) {
        fileError = error.localizedDescription
    }

    public func recordDiscardedEdits(_ count: Int) {
        discardedEditCount += count
    }

    public func dismiss() {
        saveError = nil
        fileError = nil
        discardedEditCount = 0
    }
}
