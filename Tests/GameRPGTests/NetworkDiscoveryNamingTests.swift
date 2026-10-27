// @copyright André Trettin

#if canImport(Testing)
import Foundation
import Testing

@testable import GameRPG

@Suite("Discovery naming and configuration — CODE_AUDIT_Join")
@MainActor
struct NetworkDiscoveryNamingTests {
    @Test("Advertised names are trimmed, non-empty and at most 63 UTF-8 bytes (§5.10)")
    func advertisedNameIsBounded() {
        let long = String(repeating: "é", count: 60)
        let name = ListenerServerController.advertisedName(from: long)

        #expect(name.utf8.count <= 63)
        #expect(long.hasPrefix(name))
        #expect(!name.isEmpty)
        #expect(ListenerServerController.advertisedName(from: "   ") == "MasterRPG")
        #expect(ListenerServerController.advertisedName(from: "  Curse of Strahd \n") == "Curse of Strahd")
    }

    @Test("A title containing a dot is shown whole (§5.10)")
    func deviceNameKeepsDots() {
        func model(_ name: String) -> BrowserGameModel {
            BrowserGameModel(id: UUID(), endpointName: name, connectionMode: .observer)
        }
        #expect(model("Curse of Strahd Vol. 2").deviceName == "Curse of Strahd Vol. 2")
        #expect(model("Morgan.MasterRPG").deviceName == "Morgan")
    }

    /// `#filePath` is where the test bundle was built. A runner that only receives the built
    /// bundle (Xcode Cloud test runs) has no checkout there.
    nonisolated private static let repositoryRoot = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    nonisolated fileprivate static var plistsAreOnDisk: Bool {
        FileManager.default.fileExists(atPath: repositoryRoot.appending(path: "Resources/Info.plist").path(percentEncoded: false))
    }

    @Test(
        "Every service type is declared in both Info.plist files (§9.4)",
        .enabled(if: NetworkDiscoveryNamingTests.plistsAreOnDisk, "The Info.plist files are not on the machine that runs the tests (CI)")
    )
    func serviceTypesAreDeclaredInPlists() throws {
        let services = [GameServiceType.player, .master, .proxyServer, .proxyClient].map(\.serviceName)
        let repositoryRoot = Self.repositoryRoot
        for plistName in ["Info.plist", "InfoTV.plist"] {
            let url = repositoryRoot.appending(path: "Resources").appending(path: plistName)
            let data = try Data(contentsOf: url)
            let plist = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
            let declared = try #require(plist["NSBonjourServices"] as? [String])
            for service in services {
                #expect(declared.contains(service), "\(plistName) is missing \(service)")
            }
        }
    }
}
#endif
