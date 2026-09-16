// @copyright André Trettin

import Foundation
import CloudKit
import os.log
import SwiftUI

public enum CloudKitAccountStatus: Sendable {
    case notChecked
    case noAccount
    case available
    /// The device is under a restriction the user can't fix from within this app (e.g.
    /// Screen Time / MDM). Distinct from `.unavailable` so the UI doesn't imply retrying
    /// might help. See CODE_AUDIT §8.1.
    case restricted
    /// A transient, often self-resolving condition (per `CKAccountStatus.temporarilyUnavailable`,
    /// e.g. mid account-migration). Distinct from `.unavailable` so the UI can suggest
    /// retrying instead of implying a persistent problem. See CODE_AUDIT §8.1.
    case temporarilyUnavailable
    case unavailable

    public var title: String {
        switch self {
        case .notChecked:
            return "Not checked".localizedString
        case .noAccount:
            return "No Account".localizedString
        case .available:
            return "Available".localizedString
        case .restricted:
            return "Restricted by Device Settings".localizedString
        case .temporarilyUnavailable:
            return "Temporarily Unavailable".localizedString
        case .unavailable:
            return "Unavailable".localizedString
        }
    }
}

public struct CloudKitAccountController {
    public static func checkAccountStatus() async -> CloudKitAccountStatus {
        let result = CKContainer.default().accountStatus
        do {
            let status = try await result()
            switch status {
            case .available:
                return .available
            case .noAccount:
                return .noAccount
            case .restricted:
                return .restricted
            case .temporarilyUnavailable:
                return .temporarilyUnavailable
            case .couldNotDetermine:
                return .unavailable
            @unknown default:
                return .unavailable
            }
        } catch {
            Logger.persistenceController.error("Cannot check iCloud account: \(error.localizedDescription, privacy: .public)")
        }
        return .unavailable
    }
}
