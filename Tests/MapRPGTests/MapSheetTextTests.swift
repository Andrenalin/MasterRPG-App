// @copyright André Trettin

#if canImport(Testing) && !os(tvOS)
import CoreRPG
import Foundation
import Testing

@testable import MapRPG
@testable import PhotoRPG

/// The text the Map "Extract Information" analyzes and the hint to describe the map photo.
@MainActor
@Suite("Map sheet text for the AI extraction")
struct MapSheetTextTests {
    private func photoId(in root: MapRootModel) throws -> UUID {
        let photos = root.photoRoot.itemControllable
        return try #require(photos.itemDataModel.items.first { photos.itemSync(for: $0)?.specialCategory == false })
    }

    private func map(photoId: UUID?, entries: [MapEntryModel]? = nil) -> MapModel {
        MapModel(
            id: UUID(),
            name: "Old Mill",
            entries: entries ?? [MapEntryModel(id: UUID(), name: "Grinding room", content: "A broken millstone.", coordinates: [])],
            photoId: photoId
        )
    }

    private func setPhoto(_ photoId: UUID, description: String, tags: [String], in root: MapRootModel) {
        root.photoRoot.editController.reset(name: nil, description: description, tags: tags, itemId: photoId, forceSave: true)
    }

    @Test("Without a photo the hint is shown and the text has no photo lines")
    func noPhoto() async throws {
        let root = try await MockRoot.importTestData()
        let model = map(photoId: nil)

        #expect(!MapSheetText.hasPhotoText(for: model, photoRoot: root.photoRoot))
        let text = MapSheetText.text(for: model, photoRoot: root.photoRoot)
        #expect(text.hasSuffix("- Grinding room: A broken millstone."))
        #expect(!text.contains("Map photo"))
    }

    @Test("A photo without description and tags shows the hint")
    func emptyPhoto() async throws {
        let root = try await MockRoot.importTestData()
        let photoId = try photoId(in: root)
        setPhoto(photoId, description: "", tags: [], in: root)
        let model = map(photoId: photoId)

        #expect(!MapSheetText.hasPhotoText(for: model, photoRoot: root.photoRoot))
        #expect(!MapSheetText.text(for: model, photoRoot: root.photoRoot).contains("Map photo"))
    }

    @Test("A photo description or tags alone hide the hint and reach the text")
    func describedPhoto() async throws {
        let root = try await MockRoot.importTestData()
        let photoId = try photoId(in: root)
        let model = map(photoId: photoId)

        setPhoto(photoId, description: "A watermill beside a river.", tags: [], in: root)
        #expect(MapSheetText.hasPhotoText(for: model, photoRoot: root.photoRoot))
        #expect(MapSheetText.text(for: model, photoRoot: root.photoRoot).contains("\nMap photo: A watermill beside a river."))

        setPhoto(photoId, description: "", tags: ["Mill", "River"], in: root)
        #expect(MapSheetText.hasPhotoText(for: model, photoRoot: root.photoRoot))
        #expect(MapSheetText.text(for: model, photoRoot: root.photoRoot).contains("\nMap photo tags: Mill, River\n"))
    }

    @Test("The photo comes before the rooms, so a long room list cannot cut it off")
    func photoBeforeRooms() async throws {
        let root = try await MockRoot.importTestData()
        let photoId = try photoId(in: root)
        setPhoto(photoId, description: "A watermill beside a river.", tags: ["Mill", "River"], in: root)

        #expect(MapSheetText.text(for: map(photoId: photoId), photoRoot: root.photoRoot) == """
        Map: Old Mill
        Map photo: A watermill beside a river.
        Map photo tags: Mill, River

        - Grinding room: A broken millstone.
        """)
    }

    @Test("The hex grid is no room: a map with only a hex grid has no text, so the batch skips it")
    func hexGridOnly() async throws {
        let root = try await MockRoot.importTestData()
        let hexGrid = MapEntryModel(id: UUID(), name: "Hex grid", content: "", coordinates: [], isHexGrid: true)

        #expect(MapSheetText.rooms(of: map(photoId: nil, entries: [hexGrid])).isEmpty)
        #expect(MapSheetText.text(for: map(photoId: nil, entries: [hexGrid]), photoRoot: root.photoRoot).isEmpty)
        #expect(MapSheetText.text(for: map(photoId: nil, entries: []), photoRoot: root.photoRoot).isEmpty)
    }
}
#endif
