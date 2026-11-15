// @copyright André Trettin

import Foundation
import Testing

@testable import CoreRPG

/// CODE_AUDIT_26 §5.10: `download(fileUrl:)` resolves the stored URL through its decoded components.
@Suite("Cloud download path")
struct CloudDownloadPathTests {
    @Test("A stored URL with a space and a non-ASCII letter resolves to that exact file name",
          arguments: ["Map Name é.png", "Token #1.webp", "What? Why.pdf", "100% sure.png"])
    func downloadUrlUsesTheDecodedName(name: String) throws {
        let controller = CloudDocumentController(modulePath: "Photos")
        var stored = URL(string: "/")!
        stored.append(path: name)

        let resolved = try controller.downloadUrl(for: stored)

        #expect(resolved.lastPathComponent == name)
        #expect(!resolved.lastPathComponent.contains("%2") || name.contains("%2"))
        #expect(resolved == controller.fullUrl(fileUrl: stored))
    }

    @Test("The old route through the encoded string double-encoded the name")
    func encodedStringWasWrong() throws {
        let controller = CloudDocumentController(modulePath: "Photos")
        var stored = URL(string: "/")!
        stored.append(path: "Map Name.png")

        let viaString = try #require(controller.fullUrl(filePath: stored.absoluteString))
        #expect(viaString.lastPathComponent != "Map Name.png")
        #expect(try controller.downloadUrl(for: stored).lastPathComponent == "Map Name.png")
    }
}
