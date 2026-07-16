// @copyright André Trettin

import Foundation

enum FoundationModelCoreError: LocalizedError, Sendable, Equatable {
    case invalidRequest(String)
    case unavailableCapability(String)
    case providerFailure(String)
    case unsupportedEnvironment(String)

    var errorDescription: String? {
        switch self {
        case .invalidRequest(let message):
            return String(localized: "Invalid request: \(message)", bundle: .module)
        case .unavailableCapability(let message):
            return String(localized: "Unavailable capability: \(message)", bundle: .module)
        case .providerFailure(let message):
            return String(localized: "Provider failure: \(message)", bundle: .module)
        case .unsupportedEnvironment(let message):
            return String(localized: "Unsupported environment: \(message)", bundle: .module)
        }
    }
}
