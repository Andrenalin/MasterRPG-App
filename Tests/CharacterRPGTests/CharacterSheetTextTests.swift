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
        #expect(!CharacterSheetText.text(for: model, photoRoot: root.photoRoot, resolve: { _ in nil }).contains("Portrait"))
    }

    @Test("A portrait without description and tags shows the hint")
    func emptyPortrait() async throws {
        let root = try await MockRoot.importTestData()
        let photoId = try photoId(in: root)
        setPortrait(photoId, description: "", tags: [], in: root)
        let model = character(photoId: photoId)

        #expect(!CharacterSheetText.hasPortraitText(for: model, photoRoot: root.photoRoot))
        #expect(!CharacterSheetText.text(for: model, photoRoot: root.photoRoot, resolve: { _ in nil }).contains("Portrait"))
    }

    @Test("A portrait description or tags alone hide the hint and reach the text")
    func describedPortrait() async throws {
        let root = try await MockRoot.importTestData()
        let photoId = try photoId(in: root)
        let model = character(photoId: photoId)

        setPortrait(photoId, description: "A bearded dwarf with a warhammer.", tags: [], in: root)
        #expect(CharacterSheetText.hasPortraitText(for: model, photoRoot: root.photoRoot))
        #expect(CharacterSheetText.text(for: model, photoRoot: root.photoRoot, resolve: { _ in nil }).contains("\nPortrait: A bearded dwarf with a warhammer."))

        setPortrait(photoId, description: "", tags: ["Dwarf", "Warhammer"], in: root)
        #expect(CharacterSheetText.hasPortraitText(for: model, photoRoot: root.photoRoot))
        #expect(CharacterSheetText.text(for: model, photoRoot: root.photoRoot, resolve: { _ in nil }).hasSuffix("\nPortrait tags: Dwarf, Warhammer"))
    }

    // MARK: - Groups

    private func group(_ name: String, entries: [ValueEntryModel]) -> ValueModel {
        ValueModel(id: UUID(), name: name, entries: entries)
    }

    private func value(_ name: String, _ value: String) -> ValueEntryModel {
        ValueEntryModel(id: UUID(), name: name, type: .text, value: value)
    }

    private func groupEntry(_ name: String, to group: ValueModel) -> ValueEntryModel {
        ValueEntryModel(id: UUID(), name: name, type: .text, value: "", valueId: group.id)
    }

    @Test("A group is its name followed by its own values, so race and player reach the model")
    func groupIsExpanded() {
        let basics = group("Adalbert's Group", entries: [value("Rasse", "Gnom"), value("Spieler", "Karsten")])
        let model = ValueModel(id: UUID(), name: "Adalbert Unheil", entries: [groupEntry("Basiswerte", to: basics), value("Zauber", "Feuerstrahl")])
        let groups = [basics.id: basics]

        let text = CharacterSheetText.text(for: model, photoRoot: nil, resolve: { groups[$0] })

        #expect(text.contains("- Basiswerte\n- Rasse: Gnom\n- Spieler: Karsten\n- Zauber: Feuerstrahl"))
        #expect(!text.contains("Adalbert's Group"))
    }

    @Test("Groups inside groups are followed")
    func nestedGroups() {
        let inner = group("Inner", entries: [value("Kultur", "Narrländer")])
        let outer = group("Outer", entries: [groupEntry("Herkunft", to: inner)])
        let model = ValueModel(id: UUID(), name: "Adalbert", entries: [groupEntry("Basiswerte", to: outer)])
        let groups = [inner.id: inner, outer.id: outer]

        #expect(CharacterSheetText.text(for: model, photoRoot: nil, resolve: { groups[$0] }).contains("- Basiswerte\n- Herkunft\n- Kultur: Narrländer"))
    }

    @Test("A group that links back or is missing keeps only its name and does not loop")
    func cyclicAndMissingGroups() {
        let modelId = UUID()
        let loop = ValueModel(id: UUID(), name: "Loop", entries: [
            value("Rasse", "Gnom"),
            ValueEntryModel(id: UUID(), name: "Zurück", type: .text, value: "", valueId: modelId)
        ])
        let model = ValueModel(id: modelId, name: "Adalbert", entries: [
            groupEntry("Basiswerte", to: loop),
            ValueEntryModel(id: UUID(), name: "Fehlt", type: .text, value: "", valueId: UUID())
        ])
        let groups = [loop.id: loop, modelId: model]

        let text = CharacterSheetText.text(for: model, photoRoot: nil, resolve: { groups[$0] })

        #expect(text.hasSuffix("- Basiswerte\n- Rasse: Gnom\n- Zurück\n- Fehlt"))
    }

    @Test("A character without values has no text, so the batch skips it")
    func noValues() async throws {
        let root = try await MockRoot.importTestData()
        let model = ValueModel(id: UUID(), name: "Empty")

        #expect(CharacterSheetText.text(for: model, photoRoot: root.photoRoot, resolve: { _ in nil }).isEmpty)
    }
}
#endif
