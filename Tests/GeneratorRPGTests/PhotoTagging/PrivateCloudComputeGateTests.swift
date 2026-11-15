// @copyright André Trettin

#if !os(tvOS)

import Testing

@testable import GeneratorRPG

/// CODE_AUDIT_26 §6.14: the cloud needs the host's entitlement, not only the module's build flag.
@Suite("Private Cloud Compute gate")
struct PrivateCloudComputeGateTests {
    @Test("Without the compile-time flag the cloud is off whatever the host says")
    func flagIsRequired() {
        #expect(!PrivateCloudComputeGate.isEnabled(compileTimeFlag: false, processEntitlement: true, hostDeclaration: true))
    }

    @Test("A host that does not declare the entitlement keeps the cloud off")
    func undeclaredHostStaysOff() {
        #expect(!PrivateCloudComputeGate.isEnabled(compileTimeFlag: true, processEntitlement: nil, hostDeclaration: false))
        #expect(PrivateCloudComputeGate.isEnabled(compileTimeFlag: true, processEntitlement: nil, hostDeclaration: true))
    }

    @Test("A readable process entitlement wins over the declaration")
    func processEntitlementWins() {
        #expect(!PrivateCloudComputeGate.isEnabled(compileTimeFlag: true, processEntitlement: false, hostDeclaration: true))
        #expect(PrivateCloudComputeGate.isEnabled(compileTimeFlag: true, processEntitlement: true, hostDeclaration: false))
    }

    @Test("The build without the flag reports the cloud as off")
    func currentBuildIsOff() {
        // The flag is not defined on any target yet; this fails the day it is, as a reminder
        // that the hosts must then declare the entitlement.
        #expect(!PhotoSummaryAnalyzer.isPrivateCloudComputeEnabled)
    }
}

#endif
