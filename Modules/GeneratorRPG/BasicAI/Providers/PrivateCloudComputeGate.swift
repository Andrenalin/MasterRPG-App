// @copyright André Trettin

#if !os(tvOS)

import Foundation
import Security
import Synchronization

/// Whether the process may create a `PrivateCloudComputeLanguageModel`. Creating one without the
/// managed entitlement `com.apple.developer.private-cloud-compute` is a fatal error.
///
/// The compile-time condition `PRIVATE_CLOUD_COMPUTE_ENTITLED` belongs to the GeneratorRPG target,
/// but every host app (MasterRPG, MasterMac, the share extension...) links the same module, and
/// only some of them carry the entitlement. So the condition alone is not enough: the cloud also
/// needs the host's own entitlement. On macOS it is read from the process's code signature; on
/// the other platforms no public API reads it, so the host declares it once at launch with
/// `PhotoSummaryAnalyzer.declareHostPrivateCloudComputeEntitlement(_:)`. A host that does not
/// declare it keeps the cloud off. See CODE_AUDIT_26 §6.14.
///
/// To enable the cloud: get the entitlement approved, add it to the host's entitlement files,
/// define `PRIVATE_CLOUD_COMPUTE_ENTITLED` on the GeneratorRPG target and call the declaration
/// from every host that has it.
enum PrivateCloudComputeGate {
    static let entitlementKey = "com.apple.developer.private-cloud-compute"

    private static let declaration = Mutex<Bool>(false)

    static func declareHost(entitled: Bool) {
        declaration.withLock { $0 = entitled }
    }

    static var isHostDeclaredEntitled: Bool {
        declaration.withLock { $0 }
    }

    /// The decision, pure so it is tested. The process's own entitlement (`nil` when it cannot be
    /// read) wins over the host's declaration, so a signed process without it never enables the
    /// cloud.
    static func isEnabled(compileTimeFlag: Bool, processEntitlement: Bool?, hostDeclaration: Bool) -> Bool {
        guard compileTimeFlag else { return false }
        return processEntitlement ?? hostDeclaration
    }

    /// The entitlement of this process on macOS, `nil` where it cannot be read.
    static func processEntitlement() -> Bool? {
#if os(macOS)
        guard let task = SecTaskCreateFromSelf(nil) else { return nil }
        let value = SecTaskCopyValueForEntitlement(task, entitlementKey as CFString, nil)
        return (value as? Bool) ?? false
#else
        return nil
#endif
    }
}

#endif
