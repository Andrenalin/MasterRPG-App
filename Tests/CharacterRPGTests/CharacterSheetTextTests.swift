// @copyright André Trettin

#if canImport(Testing) && !os(tvOS)
import CoreRPG
import Foundation
import Testing

@testable import CharacterRPG
@testable import PhotoRPG

/// The text the Character "Extract Information" analyzes and the hint to describe the portrait.
@MainActor
@Suite("Character sheet text for the AI extraction")
struct CharacterSheetTextTests {
    private func photoId(in root: CharacterRootModel) throws -> UUID {
        let photos = root.photoRoot.itemControllable
        return try #require(photos.itemDataModel.items.first { photos.itemSync(for: $0)?.specialCategory == false })
    }

    private func character(photoId: UUID?) -> ValueModel {
        ValueModel(
            id: UUID(),
            name: "Brakka",
            photoId: photoId,
            entries: [ValueEntryModel(id: UUID(), name: "Class", type: .text, value: "Fighter")]
        )
    }

    private func setPortrait(_ photoId: UUID, description: String, tags: [String], in root: CharacterRootModel) {
        root.photoRoot.editController.reset(name: nil, description: description, tags: tags, itemId: photoId, forceSave: true)
    }

    @Test("Without a portrait the hint is shown and the text has no portrait lines")
    func noPortrait() async throws {
        let root = try await MockRoot.importTestData()
        let model = character(photoId: nil)

        #expect(!CharacterSheetText.hasPortraitText(for: model, photoRoot: root.photoRoot))
        #expect(!CharacterSheetText.text(for: model, photoRoot: root.photoRoot).contains("Portrait"))
    }

    @Test("A portrait without description and tags shows the hint")
    func emptyPortrait() async throws {
        let root = try await MockRoot.importTestData()
        let photoId = try photoId(in: root)
        setPortrait(photoId, description: "", tags: [], in: root)
        let model = character(photoId: photoId)

        #expect(!CharacterSheetText.hasPortraitText(for: model, photoRoot: root.photoRoot))
        #expect(!CharacterSheetText.text(for: model, photoRoot: root.photoRoot).contains("Portrait"))
    }

    @Test("A portrait description or tags alone hide the hint and reach the text")
    func describedPortrait() async throws {
        let root = try await MockRoot.importTestData()
        let photoId = try photoId(in: root)
        let model = character(photoId: photoId)

        setPortrait(photoId, description: "A bearded dwarf with a warhammer.", tags: [], in: root)
        #expect(CharacterSheetText.hasPortraitText(for: model, photoRoot: root.photoRoot))
        #expect(CharacterSheetText.text(for: model, photoRoot: root.photoRoot).contains("\nPortrait: A bearded dwarf with a warhammer."))

        setPortrait(photoId, description: "", tags: ["Dwarf", "Warhammer"], in: root)
        #expect(CharacterSheetText.hasPortraitText(for: model, photoRoot: root.photoRoot))
        #expect(CharacterSheetText.text(for: model, photoRoot: root.photoRoot).hasSuffix("\nPortrait tags: Dwarf, Warhammer"))
    }

    @Test("A character without values has no text, so the batch skips it")
    func noValues() async throws {
        let root = try await MockRoot.importTestData()
        let model = ValueModel(id: UUID(), name: "Empty")

        #expect(CharacterSheetText.text(for: model, photoRoot: root.photoRoot).isEmpty)
    }
}
#endif
