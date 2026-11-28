// @copyright André Trettin

import CoreRPG
import Foundation
import Testing

@testable import CharacterRPG

@Suite("Value model tests")
@MainActor
struct ValueModelTests {
    /// Creates a test ValueModel with one entry for testing.
    ///
    /// Uses the fixture pattern to provide sensible defaults while allowing customization.
    static func makeValueModel(
        name: String = "Some Name",
        description: String = "Some Desc"
    ) -> ValueModel {
        ValueModel(
            id: UUID(),
            name: name,
            description: description,
            tags: ["Hi", "Good"],
            category: .gameMaster,
            displayState: 2,
            photoId: UUID(),
            photos: [UUID(), UUID()],
            entries: [
                ValueEntryModel.fixture(name: "Nice", type: .decimal, value: "0"),
            ]
        )
    }

    @Test func assignAndDuplicate() async throws {
        // Arrange
        let sut = Self.makeValueModel()
        let a = sut
        #expect(a == sut)

        let d = sut.duplicate()
        #expect(d.id != a.id)
        #expect(d.name == "\(a.name) Copy")
        #expect(d.description == a.description)
        #expect(d.tags == a.tags)
        #expect(d.category == a.category)
        #expect(d.displayState == a.displayState)

        #expect(d.photoId == a.photoId)
        #expect(d.photos == a.photos)

        #expect(d.entries.count == a.entries.count)
        for (index, _) in d.entries.enumerated() {
            #expect(d.entries[index] != a.entries[index])
            #expect(d.entries[index].isSame(a.entries[index]))
        }
    }

    @Test func changeValues() async throws {
        // Arrange
        let sut = Self.makeValueModel()
        let a = sut.copy()
        let b = sut.copy()
        let c = sut.copy()
        #expect(sut.isSame(a) == true)
        a.name = "Oh no"
        #expect(sut.isSame(a) == false)
        var entries = b.entries
        entries[0].value = "some other"
        b.entries = entries
        #expect(b.entries[0].value == "some other")
        #expect(sut.isSame(b) == false)
        c.entries = c.entries + [ValueEntryModel(id: UUID(), name: "Two", type: .decimal, value: "0")]
        #expect(c.entries.count == 2)
        #expect(sut.isSame(c) == false)

        a.name = "Good"
        #expect(sut.isSame(a) == false)

        sut.description = "New Description"
        sut.tags = ["Second"]
        sut.category = .character
        sut.name = "Take this"
        a.tags = ["DS"]
        a.displayState = 100
        a.photos = [UUID()]
        sut.photoId = UUID()

        let m1 = a.merge(sut)
        #expect(m1.id == a.id)
        #expect(m1.name == sut.name)
        #expect(m1.description == sut.description)
        #expect(m1.tags == a.tags)
        #expect(m1.category == sut.category)
        #expect(m1.displayState == sut.displayState)
        #expect(m1.photoId == sut.photoId)
        #expect(m1.photos == a.photos)
        #expect(m1.entries == a.entries)

        let m2 = sut.merge(a)
        #expect(m2.id == a.id)
        #expect(m2.name == sut.name)
        #expect(m2.description == sut.description)
        #expect(m2.tags == a.tags)
        #expect(m2.category == sut.category)
        #expect(m2.displayState == a.displayState)
        #expect(m2.photoId == sut.photoId)
        #expect(m2.photos == a.photos)
        #expect(m2.entries == sut.entries)
    }

    @Test("Character version is stable and tracks Character content including the player photo")
    func stableCharacterVersion() throws {
        // Given
        let characterId = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let photoId = try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
        let listedPhotoId = try #require(UUID(uuidString: "33333333-3333-3333-3333-333333333333"))
        let entryId = try #require(UUID(uuidString: "44444444-4444-4444-4444-444444444444"))
        let diceId = try #require(UUID(uuidString: "55555555-5555-5555-5555-555555555555"))
        let linkedValueId = try #require(UUID(uuidString: "66666666-6666-6666-6666-666666666666"))
        let replacementPhotoId = try #require(UUID(uuidString: "77777777-7777-7777-7777-777777777777"))
        let makeCharacter = {
            ValueModel(
                id: characterId,
                name: "Mira",
                description: "Scout",
                tags: ["player"],
                category: .character,
                displayState: 2,
                photoId: photoId,
                photos: [listedPhotoId],
                entries: [
                    ValueEntryModel(
                        id: entryId,
                        name: "Agility",
                        type: .number,
                        isGenerator: true,
                        value: "12",
                        diceId: diceId,
                        valueId: linkedValueId,
                        displayState: 1
                    ),
                ],
                parentId: linkedValueId,
                diceId: diceId,
                groupId: linkedValueId
            )
        }
        let character = makeCharacter()
        let independentlyCreated = makeCharacter()
        let originalVersion = character.version

        // When / Then
        #expect(originalVersion != 0)
        #expect(independentlyCreated.version == originalVersion)

        let renamedCharacter = character.copy()
        renamedCharacter.name = "Mira Swiftstep"
        #expect(renamedCharacter.version != originalVersion)

        let changedEntryCharacter = character.copy()
        var changedEntries = changedEntryCharacter.entries
        changedEntries[0].value = "13"
        changedEntryCharacter.entries = changedEntries
        #expect(changedEntryCharacter.version != originalVersion)

        let changedPhotoCharacter = character.copy()
        changedPhotoCharacter.photoId = replacementPhotoId
        #expect(changedPhotoCharacter.version != originalVersion)
    }

    @Test func folderMergeCombinesAndSortsChildren() {
        let folderId = UUID()
        let folder1 = ValueModel(
            id: folderId,
            name: "Folder",
            category: .folder,
            entries: [
                ValueEntryModel.fixture(name: "Bravo"),
                ValueEntryModel.fixture(name: "Alpha"),
            ]
        )
        let folder2 = ValueModel(
            id: folderId,
            name: "Folder",
            category: .folder,
            entries: [
                ValueEntryModel.fixture(name: "Delta"),
                ValueEntryModel.fixture(name: "Charlie"),
            ]
        )

        let merged = folder1.merge(folder2)
        #expect(merged.entries.count == 4)
        #expect(merged.entries.map(\.name) == ["Alpha", "Bravo", "Charlie", "Delta"])

        let collection1 = ValueModel(
            id: folderId,
            name: "Collection",
            category: .collection,
            entries: [
                ValueEntryModel.fixture(name: "Delta"),
                ValueEntryModel.fixture(name: "Charlie"),
            ]
        )

        let merged2 = folder1.merge(collection1)
        #expect(merged2.entries.count == 2)
        #expect(merged2.entries.map(\.name) == ["Delta", "Charlie"])
    }
}
