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
