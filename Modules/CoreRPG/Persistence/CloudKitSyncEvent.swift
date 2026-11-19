// @copyright André Trettin

import CloudKit
import CoreData
import Foundation
import os.log

/// What a CloudKit container event says, without the framework type: `NSPersistentCloudKitContainer.Event`
/// cannot be built outside the framework, so the mapping to `CloudKitSyncState` works on this copy.
struct CloudKitSyncEvent: Sendable {
    enum Kind: Sendable {
        case setup
        case `import`
        case export
        case unknown
    }

    let kind: Kind
    let succeeded: Bool
    let error: (any Error)?

    init(kind: Kind, succeeded: Bool, error: (any Error)? = nil) {
        self.kind = kind
        self.succeeded = succeeded
        self.error = error
    }

    init(_ event: NSPersistentCloudKitContainer.Event) {
        let kind: Kind = switch event.type {
        case .setup: .setup
        case .import: .import
        case .export: .export
        @unknown default: .unknown
        }
        self.init(kind: kind, succeeded: event.succeeded, error: event.error)
    }
}

/// The change one event makes to the model. See CODE_AUDIT_17 §5.8 for why failures must surface.
enum CloudKitEventModelUpdate: Sendable, Equatable {
    case none
    case syncState(CloudKitSyncState)
    case importSucceeded(Date)
    case exportSucceeded(Date)
}

extension CloudKitSyncEvent {
    /// A finished event succeeds or fails; an event without a result and without an error is
    /// still running. A failed setup, import or export is surfaced instead of being masked as
    /// "in progress" or left at the last "succeeded".
    func modelUpdate(now: Date = .now) -> CloudKitEventModelUpdate {
        switch kind {
        case .setup:
            if succeeded {
                Logger.persistenceController.info("CloudKit setup succeeded")
                return .none
            }
            if let error {
                Logger.persistenceController.error("CloudKit setup failed: \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private)")
                return .syncState(.failed(error.localizedDescription))
            }
            Logger.persistenceController.info("CloudKit setup in progress")
            return .syncState(.inProgress)

        case .import:
            if succeeded {
                Logger.persistenceController.info("CloudKit import succeeded")
                return .importSucceeded(now)
            }
            if let error {
                Logger.persistenceController.error("CloudKit import error: \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private)")
                return .syncState(.failed(error.localizedDescription))
            }
            return .syncState(.inProgress)

        case .export:
            if succeeded {
                Logger.persistenceController.info("CloudKit export succeeded")
                return .exportSucceeded(now)
            }
            if let error {
                Logger.persistenceController.error("CloudKit export error: \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private)")
                return .syncState(.failed(error.localizedDescription))
            }
            return .syncState(.inProgress)

        case .unknown:
            Logger.persistenceController.debug("CloudKit unknown event type")
            return .none
        }
    }
}

extension CoreDataInitModel {
    /// Applies an event's update to the state the UI shows. A successful import or export clears
    /// a failed or in-progress state and records the time.
    func apply(_ update: CloudKitEventModelUpdate) {
        switch update {
        case .none:
            break
        case .syncState(let state):
            cloudKitSyncState = state
        case .importSucceeded(let date), .exportSucceeded(let date):
            cloudKitSyncState = .succeeded
            lastSuccessfulSync = date
        }
    }
}
