// @copyright André Trettin

import CoreRPG
import Foundation
import Testing

@testable import RolePlayGameKit

/// CODE_AUDIT §5.14: a file name is not a URL. `#` and `?` in `Crypt #2.dd2vtt` must not cut the
/// image extension off the plan, or the import fails with "image could not be decoded".
@MainActor
@Suite("Universal VTT file names")
struct UniversalVTTDomainMapperFileNameTests {
    @Test("A file name with # or ? still yields an image attachment", arguments: ["Crypt #2.dd2vtt", "What? Cave.dd2vtt", "plain.dd2vtt"])
    func fileNameWithSpecialCharacters(fileName: String) async throws {
        let mapped = try await UniversalVTTDomainMapper().map(
            document: document(),
            sourceUrl: URL(filePath: "/tmp/\(fileName)"),
            sourceScopeId: try #require(UUID(uuidString: "5C0B1A57-3F3E-4D0B-9B52-0E3B8F6F2A13")),
            resourceLoader: { _ in Data() }
        )

        let photo = try #require(mapped.batch.items.first { $0.module == .photo })
        let attachment = try #require(photo.attachment)
        #expect(attachment.suggestedFilename.hasSuffix(".jpg"))
    }

    private func document() -> UniversalVTTDocument {
        UniversalVTTDocument(
            formatVersion: 0.3,
            resolution: UniversalVTTResolution(
                mapOrigin: UniversalVTTPoint(x: 0, y: 0),
                mapSize: UniversalVTTPoint(x: 10, y: 10),
                pixelsPerGrid: 50
            ),
            lineOfSight: [],
            portals: [],
            lights: [],
            imageResource: FoundryPackageResource(
                logicalPath: "embedded-map.png",
                packagePath: nil,
                location: .packaged,
                byteCount: nil,
                sha256: nil
            ),
            rawData: .object([:])
        )
    }
}
