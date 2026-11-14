// @copyright André Trettin

import Foundation
import Testing

@testable import CoreRPG

/// The ids are stored and synced, so the derivation must give the same value on every device
/// and release. The expected values were computed once, independently (SHA-256 of the key, the
/// first 16 bytes, version and variant bits), from the code the helper replaced.
/// See CODE_AUDIT §9.6.
@Suite("Deterministic UUID")
struct DeterministicUUIDTests {
    @Test("The v8 ids of Foundry sources keep their values")
    func foundryIdentityIsStable() {
        #expect(FoundryRuleIdentity.uuid(for: "map-wall:abc") == UUID(uuidString: "24A53D30-DFC9-846A-8C36-36BF7C4A0E58"))
        #expect(DeterministicUUID.uuid(hashing: "map-wall:abc", version: .v8) == FoundryRuleIdentity.uuid(for: "map-wall:abc"))
    }

    @Test("The v5-shaped id of a scanned iCloud path keeps its value")
    func cloudFolderScanIdIsStable() {
        let id = CloudFolderScan.derivedId(module: "Photos", path: ["maps", "a.png"], isFolder: false)
        #expect(id == UUID(uuidString: "3E265AE6-D91A-5847-A0CF-FE4813E4CC65"))
    }

    @Test("An empty key is still a valid id")
    func emptyKey() {
        #expect(DeterministicUUID.uuid(hashing: "", version: .v5) == UUID(uuidString: "E3B0C442-98FC-5C14-9AFB-F4C8996FB924"))
    }

    @Test("Version and variant bits are set, and the same key gives the same id")
    func versionAndVariant() {
        for (version, nibble) in [(DeterministicUUID.Version.v5, UInt8(5)), (.v8, 8)] {
            let id = DeterministicUUID.uuid(hashing: "key", version: version)
            #expect(id == DeterministicUUID.uuid(hashing: "key", version: version))
            #expect(id.uuid.6 >> 4 == nibble)
            #expect(id.uuid.8 >> 6 == 0b10)
        }
        #expect(DeterministicUUID.uuid(hashing: "key", version: .v5) != DeterministicUUID.uuid(hashing: "key", version: .v8))
    }

    @Test("Sixteen bytes become the same UUID, unchanged")
    func bytesAreKept() {
        let bytes: [UInt8] = Array(0..<16)
        let id = DeterministicUUID.uuid(bytes: bytes)
        #expect(id.uuidString == "00010203-0405-0607-0809-0A0B0C0D0E0F")
    }
}
