// @copyright André Trettin

#if canImport(Testing)
import Foundation
import Testing

@testable import AudioRPG
@testable import CoreRPG

/// A master shares an audio item that lives in a folder. A player who has neither the item nor
/// the folder gets the folder as the master has it: same id, name, kind and member list.
@Suite(.serialized)
@MainActor
struct GameImportFolderPlacementTests {
    private struct Exported {
        let package: NetworkCodableDataType
        var data: Data { package.data ?? Data() }
        let audioId: UUID
        /// The master's folders from the outermost down to the one holding the audio item.
        let folderIds: [UUID]
    }

    /// The master's library: `00 Test` inside `folderNames` (outermost first), shared as game data.
    private func masterExport(folderNames: [String]) async throws -> Exported {
        let root = AudioRootModel.testRoot()
        try await MockRoot.resetTestData(for: root)

        var folderIds: [UUID] = []
        for name in folderNames {
            let folderId = await root.itemController.addNew(type: .folder)
            root.editController.reset(name: name, itemId: folderId, forceSave: false)
            if let parentId = folderIds.last {
                root.editController.addItem(itemId: folderId, parentId: parentId)
            }
            folderIds.append(folderId)
        }
        let audioId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "00 Test", itemId: audioId, forceSave: false)
        root.editController.addItem(itemId: audioId, parentId: folderIds.last)
        try await root.editController.resetFile(data: Data("master audio".utf8), itemId: audioId, path: "00 Test.m4a", forceSave: false)

        let gameData = try await root.gameController.createGameData(for: audioId)
        _ = try #require(gameData.data)
        return Exported(package: gameData, audioId: audioId, folderIds: folderIds)
    }

    private func expectMasterFolders(_ exported: Exported, folderNames: [String], on player: AudioRootModel, noGame: Bool) throws {
        let library = player.itemController
        let audio = try #require(library.itemSync(for: exported.audioId, noGame: noGame))
        #expect(audio.name == "00 Test")
        #expect(audio.parentId == exported.folderIds.last)

        for (index, folderId) in exported.folderIds.enumerated() {
            let folder = try #require(library.itemSync(for: folderId, noGame: noGame), "the player has the master's folder \(folderNames[index])")
            #expect(folder.isFolder)
            #expect(folder.displayState == DisplayStateMask.fullVisible.rawValue, "the folder is listed, not hidden")
            #expect(folder.name == folderNames[index])
            #expect(folder.parentId == (index == 0 ? nil : exported.folderIds[index - 1]))
            let childId = index + 1 < exported.folderIds.count ? exported.folderIds[index + 1] : exported.audioId
            #expect(folder.entries.map(\.childId) == [childId], "the folder lists its member")
        }
    }

    nonisolated static let folderNameCases: [[String]] = [
        ["Audio Test Roman"],
        ["Hörspiele", "Audio Test Roman"]
    ]

    @Test("In a game the player gets the master's folder for an audio item it does not have", arguments: folderNameCases)
    func gameImportCreatesMastersFolders(folderNames: [String]) async throws {
        let exported = try await masterExport(folderNames: folderNames)

        let player = AudioRootModel.testRoot()
        try await MockRoot.resetTestData(for: player)
        player.itemController.itemDataModel.isGameMode = true
        try await player.gameController.importNetwork(from: exported.data)

        try expectMasterFolders(exported, folderNames: folderNames, on: player, noGame: false)
    }

    @Test("A saved import puts the master's folder into the player's library", arguments: folderNameCases)
    func savedImportCreatesMastersFolders(folderNames: [String]) async throws {
        let exported = try await masterExport(folderNames: folderNames)

        let player = AudioRootModel.testRoot()
        try await MockRoot.resetTestData(for: player)
        try await player.gameController.importNetwork(from: exported.data, forceSave: true)

        try expectMasterFolders(exported, folderNames: folderNames, on: player, noGame: true)
    }

    @Test("A delivery the player keeps in the library brings the master's folders with it", arguments: folderNameCases)
    func keptDeliveryStoresMastersFolders(folderNames: [String]) async throws {
        let exported = try await masterExport(folderNames: folderNames)

        // A running game: the player's library is the stored one, the game has its own memory.
        let player = AudioRootModel.testRoot()
        try await MockRoot.resetTestData(for: player)
        player.itemController.itemDataModel.isGameMode = true
        try await player.gameController.updateGame(data: exported.package, hide: false, deep: false, policy: .persist, importMode: .merge)

        // What stays after the game: without the folder the item had a parent id that points at nothing.
        try expectMasterFolders(exported, folderNames: folderNames, on: player, noGame: true)
    }

    @Test("An item whose folder was not sent is stored at the root, not under a missing parent")
    func storedItemWithoutItsFolderGoesToRoot() async throws {
        let player = AudioRootModel.testRoot()
        try await MockRoot.resetTestData(for: player)
        player.itemController.itemDataModel.isGameMode = true
        let mastersFolderId = UUID()
        let audio = AudioModel(id: UUID(), name: "00 Test", parentId: mastersFolderId)

        player.itemController.persistFromGame(model: audio, authoritative: false)

        let stored = try #require(player.itemController.itemSync(for: audio.id, noGame: true))
        #expect(stored.parentId == nil, "no folder is known, so the item is not left under the master's folder id")
    }

    // MARK: - The player already has a folder of that name

    /// The player's library with the folders `names` (outermost first) nested in each other.
    private func playerWithFolders(_ names: [String]) async throws -> (player: AudioRootModel, folderIds: [UUID]) {
        let player = AudioRootModel.testRoot()
        try await MockRoot.resetTestData(for: player)
        var ids: [UUID] = []
        for name in names {
            let folderId = await player.itemController.addNew(type: .folder)
            player.editController.reset(name: name, itemId: folderId, forceSave: false)
            if let parentId = ids.last {
                player.editController.addItem(itemId: folderId, parentId: parentId)
            }
            ids.append(folderId)
        }
        return (player, ids)
    }

    private func deliver(_ exported: Exported, to player: AudioRootModel) async throws {
        player.itemController.itemDataModel.isGameMode = true
        try await player.gameController.updateGame(data: exported.package, hide: false, deep: false, policy: .persist, importMode: .merge)
    }

    private func folders(named name: String, in player: AudioRootModel) -> [AudioModel] {
        let library = player.itemController
        return library.itemDataModel.items.compactMap { library.itemSync(for: $0, noGame: true) }
            .filter { $0.isFolder && $0.name == name }
    }

    @Test("The master's folder is matched by name to the player's own and the item moves into it",
          arguments: ["Audio Test Roman", "audio test roman"])
    func deliveredItemGoesIntoPlayersFolderOfThatName(playersName: String) async throws {
        let exported = try await masterExport(folderNames: ["Audio Test Roman"])
        let (player, playerFolderIds) = try await playerWithFolders([playersName])
        let playersFolderId = try #require(playerFolderIds.last)

        try await deliver(exported, to: player)

        let library = player.itemController
        let audio = try #require(library.itemSync(for: exported.audioId, noGame: true))
        #expect(audio.parentId == playersFolderId, "the item is in the player's folder")
        let playersFolder = try #require(library.itemSync(for: playersFolderId, noGame: true))
        #expect(playersFolder.name == playersName, "the player's folder keeps its own name")
        #expect(playersFolder.entries.map(\.childId) == [exported.audioId], "and lists the item")
        #expect(library.itemSync(for: exported.folderIds[0], noGame: true) == nil, "the master's folder is not added as a second one")
        #expect(folders(named: "Audio Test Roman", in: player).count + folders(named: "audio test roman", in: player).count == 1)
    }

    @Test("Only the outer folder exists at the player: the inner one is created inside it, the outer one is not doubled")
    func deliveredItemCreatesInnerFolderInPlayersOuterFolder() async throws {
        let names = ["Hörspiele", "Audio Test Roman"]
        let exported = try await masterExport(folderNames: names)
        let (player, playerFolderIds) = try await playerWithFolders([names[0]])
        let outerId = try #require(playerFolderIds.last)

        try await deliver(exported, to: player)

        let library = player.itemController
        #expect(folders(named: "Hörspiele", in: player).map(\.id) == [outerId], "no second outer folder")
        let inner = try #require(library.itemSync(for: exported.folderIds[1], noGame: true), "the inner folder is created as the master has it")
        #expect(inner.parentId == outerId)
        #expect(inner.entries.map(\.childId) == [exported.audioId])
        let outer = try #require(library.itemSync(for: outerId, noGame: true))
        #expect(outer.entries.map(\.childId) == [inner.id], "the player's outer folder lists the new inner folder")
        #expect(library.itemSync(for: exported.audioId, noGame: true)?.parentId == inner.id)
    }

    @Test("The player has the whole folder path: nothing is created and the item goes into the innermost folder")
    func deliveredItemGoesIntoPlayersNestedFolders() async throws {
        let names = ["Hörspiele", "Audio Test Roman"]
        let exported = try await masterExport(folderNames: names)
        let (player, playerFolderIds) = try await playerWithFolders(names)
        let innerId = try #require(playerFolderIds.last)
        let before = Set(player.itemController.itemDataModel.items)

        try await deliver(exported, to: player)

        let library = player.itemController
        #expect(Set(library.itemDataModel.items).subtracting(before) == [exported.audioId], "only the item is new")
        #expect(library.itemSync(for: exported.audioId, noGame: true)?.parentId == innerId)
        #expect(library.itemSync(for: innerId, noGame: true)?.entries.map(\.childId) == [exported.audioId])
    }

    @Test("A folder of that name at another level of the player's library is not matched")
    func sameNameAtAnotherLevelIsNotMatched() async throws {
        let exported = try await masterExport(folderNames: ["Hörspiele", "Audio Test Roman"])
        // The player's "Audio Test Roman" is in another folder than the master's.
        let (player, playerFolderIds) = try await playerWithFolders(["Sammlung", "Audio Test Roman"])
        let playersInnerId = try #require(playerFolderIds.last)

        try await deliver(exported, to: player)

        let library = player.itemController
        let audio = try #require(library.itemSync(for: exported.audioId, noGame: true))
        #expect(audio.parentId == exported.folderIds[1], "the master's path is created next to the player's folders")
        #expect(library.itemSync(for: playersInnerId, noGame: true)?.entries.isEmpty == true)
    }
}
#endif
