// @copyright André Trettin

import Foundation
import Testing

@testable import CoreRPG

/// Behavior kept by the CODE_AUDIT_26 §7 low-severity performance changes.
@Suite("Audit 26 low-severity performance fixes")
struct LowSeverityPerformanceTests {
    @MainActor
    @Test("The link register rejects a duplicate occurrence and leaves no empty arrays")
    func linkRegisterIndexes() {
        // Given
        let model = LinkRegisterListModel()
        let source = ItemRowModel(itemId: UUID(), typeId: .adventure)
        let destination = ItemRowModel(itemId: UUID(), typeId: .photo)
        let link = LinkRegisterModel(name: "", source: source, destination: destination)

        // When / Then
        #expect(model.append(link))
        #expect(!model.append(LinkRegisterModel(name: "again", source: source, destination: destination)))
        #expect(model.items[destination.itemId]?.count == 1)
        #expect(model.remove(link))
        #expect(model.items[destination.itemId] == nil)
        #expect(model.sourceItems[source.itemId] == nil)
        // The occurrence can be registered again once it was removed.
        #expect(model.append(link))
        #expect(model.removeLinks(to: destination) == [source.itemId])
        #expect(model.items.isEmpty)
        #expect(model.sourceItems.isEmpty)
    }

    @MainActor
    @Test("A restored snapshot rebuilds the duplicate index")
    func linkRegisterSnapshot() {
        // Given
        let model = LinkRegisterListModel()
        let source = ItemRowModel(itemId: UUID(), typeId: .adventure)
        let destination = ItemRowModel(itemId: UUID(), typeId: .photo)
        let link = LinkRegisterModel(name: "", source: source, destination: destination)
        model.append(link)
        let items = model.items
        let sourceItems = model.sourceItems
        model.reset()

        // When
        model.restoreSnapshot(items: items, sourceItems: sourceItems, pendingAffectedSourceIds: [])

        // Then
        #expect(!model.append(link))
    }

    @Test("The media extension is read like URL.pathExtension")
    func pathExtension() {
        let paths = [
            "systems/dnd5e/icons/sword.PNG", "a.b/c", "noextension", ".hidden", "folder/.png",
            "music/theme.ogg", "dir.jpg/", "x.tar.gz",
        ]
        for path in paths {
            #expect(
                FoundryAssetPathCollector.pathExtension(of: path) == URL(filePath: path).pathExtension.lowercased(),
                "\(path)"
            )
        }
    }

    @Test("Asset paths are found in plain strings and in inline HTML")
    func assetPaths() {
        let values: [FoundryJSONValue] = [
            .string("icons/sword.png?cache=1#top"),
            .string("<p>text <img src=\"maps/cave.webp\"> and <a href=\"notes.txt\">x</a></p>"),
            .string("no media here"),
            .string("plain.text"),
        ]

        let paths = FoundryAssetPathCollector.paths(in: values)

        #expect(paths == ["icons/sword.png?cache=1#top", "maps/cave.webp"])
    }

    @Test("Wallclock timestamps order by clock, then by actor on a tie")
    func timestampOrder() {
        let early = WallclockTimestamp(actorId: "b", timestamp: 1)
        let late = WallclockTimestamp(actorId: "a", timestamp: 2)
        let tieLow = WallclockTimestamp(actorId: "a", timestamp: 3)
        let tieHigh = WallclockTimestamp(actorId: "b", timestamp: 3)

        #expect(early < late)
        #expect(!(late < early))
        #expect(tieLow < tieHigh)
        #expect(!(tieHigh < tieLow))
    }
}
