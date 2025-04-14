// @copyright André Trettin

import Foundation
import CloudKit
import os.log
import SwiftUI

public enum CloudKitAccountStatus: Sendable {
    case notChecked
    case noAccount
    case available
    case unavailable
    
    public var title: LocalizedStringKey {
        switch self {
        case .notChecked:
            return "Not checked"
        case .noAccount:
            return "No Account"
        case .available:
            return "Available"
        case .unavailable:
            return "Unavailable"
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
            default:
                return .unavailable
            }
        } catch {
            Logger.persistenceController.error("Cannot check iCloud account: \(error.localizedDescription, privacy: .public)")
        }
        return .unavailable
    }
}
