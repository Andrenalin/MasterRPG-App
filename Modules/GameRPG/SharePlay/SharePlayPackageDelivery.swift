// @copyright André Trettin

import CoreRPG
import Foundation
import GroupActivities
import os.log

enum SharePlayPackageDeliveryError: LocalizedError, SharePlayTerminalPackageError {
    case participantNotActive(UUID)

    var errorDescription: String? {
        switch self {
        case .participantNotActive(let id):
            "SharePlay participant \(id) is no longer active"
        }
    }
}

enum SharePlayChunkedDeliveryOutcome: Equatable, Sendable {
    case succeeded
    case retryableFailure
    case terminalFailure
    case cancelled
}
