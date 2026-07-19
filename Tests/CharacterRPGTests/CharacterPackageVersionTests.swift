// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
@testable import DiceRPG
@testable import PdfRPG
@testable import PhotoRPG
@testable import TableRPG
import Testing

@testable import CharacterRPG

@Suite("Character package version")
@MainActor
struct CharacterPackageVersionTests {
    @Test("Recursive Value and player photo changes update the package version")
    func recursiveCharacterVersion() async throws {
        // Given
        let root = Self.makeRoot()
        let characterId = UUID()
        let childId = UUID()
        let character = ValueModel(
            id: characterId,
            name: "Mira",
            category: .character,
            photoId: UUID(),
            entries: [
                ValueEntryModel(
                    id: UUID(),
                    name: "Inventory",
                    type: .text,
                    value: "",
                    valueId: childId
                ),
            ]
        )
        let child = ValueModel(
            id: childId,
            name: "Inventory",
            category: .item,
            entries: [
                ValueEntryModel(id: UUID(), name: "Coins", type: .number, value: "12"),
            ]
        )
        root.itemController.replace(model: character, isInsert: true)
        root.itemController.replace(model: child, isInsert: true)
        let originalVersion = await root.gameController.networkVersion(for: characterId)

        // When / Then
        child.name = "Travel Inventory"
        let childChangedVersion = await root.gameController.networkVersion(for: characterId)
        #expect(childChangedVersion != originalVersion)

        character.photoId = UUID()
        let photoChangedVersion = await root.gameController.networkVersion(for: characterId)
        #expect(photoChangedVersion != childChangedVersion)
        #expect(photoChangedVersion != 0)

        character.tags = character.tags + ["Veteran"]
        let tagChangedVersion = await root.gameController.networkVersion(for: characterId)
        #expect(tagChangedVersion != photoChangedVersion)
    }

    @Test("Import category normalization preserves the recursive package version")
    func importCategoryNormalizationPreservesVersion() async {
        // Given
        let characterId = UUID()
        let childId = UUID()
        let portraitId = UUID()
        let characterEntryId = UUID()
        let childEntryId = UUID()
        let legacyRoot = Self.makeRoot()
        legacyRoot.itemController.replace(
            model: ValueModel(
                id: characterId,
                name: "Mira",
                tags: ["Zeta", "Alpha"],
                category: .character,
                photoId: portraitId,
                entries: [
                    ValueEntryModel(
                        id: characterEntryId,
                        name: "Inventory",
                        type: .text,
                        value: "",
                        valueId: childId
                    ),
                ]
            ),
            isInsert: true
        )
        legacyRoot.itemController.replace(
            model: ValueModel(
                id: childId,
                name: "Inventory",
                tags: ["Equipment"],
                category: .item,
                entries: [
                    ValueEntryModel(
                        id: childEntryId,
                        name: "Coins",
                        type: .number,
                        value: "12"
                    ),
                ]
            ),
            isInsert: true
        )
        let importedRoot = Self.makeRoot()
        importedRoot.itemController.replace(
            model: ValueModel(
                id: characterId,
                name: "Mira",
                tags: ImportItemRepair.normalizedTags(
                    legacyCategory: .character,
                    tags: ["Zeta", "Alpha"]
                ),
                category: .entry,
                photoId: portraitId,
                entries: [
                    ValueEntryModel(
                        id: characterEntryId,
                        name: "Inventory",
                        type: .text,
                        value: "",
                        valueId: childId
                    ),
                ]
            ),
            isInsert: true
        )
        importedRoot.itemController.replace(
            model: ValueModel(
                id: childId,
                name: "Inventory",
                tags: ImportItemRepair.normalizedTags(
                    legacyCategory: .item,
                    tags: ["Equipment"]
                ),
                category: .entry,
                entries: [
                    ValueEntryModel(
                        id: childEntryId,
                        name: "Coins",
                        type: .number,
                        value: "12"
                    ),
                ]
            ),
            isInsert: true
        )

        // When
        let advertisedVersion = await legacyRoot.gameController.networkVersion(for: characterId)
        let importedVersion = await importedRoot.gameController.networkVersion(for: characterId)

        // Then
        #expect(importedVersion == advertisedVersion)
    }

    private static func makeRoot() -> CharacterRootModel {
        let diceRoot = DiceRootModel.testRoot()
        let pdfRoot = PdfRootModel.testRoot()
        let photoRoot = PhotoRootModel.testRoot()
        let tableRoot = TableRootModel.testRoot(diceRoot: diceRoot, pdfRoot: pdfRoot)
        return CharacterRootModel.testRoot(
            diceRoot: diceRoot,
            pdfRoot: pdfRoot,
            photoRoot: photoRoot,
            tableRoot: tableRoot
        )
    }
}
#endif
