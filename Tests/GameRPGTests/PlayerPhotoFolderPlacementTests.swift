// @copyright André Trettin

#if canImport(Testing)
import AdventureRPG
import CoreRPG
import Foundation
import RPGResourcesDebug
import Testing

@testable import CharacterRPG
@testable import GameRPG
@testable import PhotoRPG

/// A player's device holds photo A (same id as the game master's) in other folders than the
/// game master does. Whatever the player sends over `PlayerController`, the master must keep A in
/// its own folder: the player's folders must not appear in the master's library, and A must not
/// be filed a second time.
@Suite("Player photo keeps the master's folder", .serialized)
@MainActor
struct PlayerPhotoFolderPlacementTests {
    /// - `masterAlreadyReportedPhoto == false`: the player has never heard of the master's copy
    ///   (no photo list yet), so the message carries the whole package including the player's
    ///   ancestor folders. This is the worst case for the master.
    /// - `masterAlreadyReportedPhoto == true`: the player names the photo by reference only.
    @Test(
        "Sharing a photo: master keeps photo A in B/C when a player sends A from D/E",
        arguments: [false, true]
    )
    func masterKeepsItsFolderForASharedPhoto(masterAlreadyReportedPhoto: Bool) async throws {
        let setup = try await Setup.make()
        let env = setup.env
        let photoId = setup.photoId

        // The player shows photo A to the group (the share button of the photo viewer).
        let playerMasterId = env.player1Root.gameModel.gameConfig.master.id
        if masterAlreadyReportedPhoto {
            let version = await env.masterRoot.photoRoot.gameController.networkVersion(for: photoId)
            env.player1Root.photoRoot.photoGameControllable.setMasterVersion(
                itemId: photoId,
                version: version,
                masterId: playerMasterId
            )
        }
        let package = try await env.player1Root.photoRoot.gameControllable.createGameData(for: photoId)
        env.playerNetworkSpy.requestHistory.removeAll()
        await env.player1.game(message: package, actionType: .generic)

        let sent = try #require(env.playerNetworkSpy.requestHistory.last as? GameNetworkModel)
        #expect(sent.type == .update)
        #expect(sent.subType == .generic)
        #expect(sent.data.id == photoId)
        if masterAlreadyReportedPhoto {
            #expect(sent.data.data == nil, "the player names the photo only")
        } else {
            #expect(sent.data.data != nil, "the player sends the whole package, with its own folders")
        }

        _ = try await env.master.handlePhoto(sent)

        setup.expectMasterLibraryUnchanged()
    }

    /// The player's Character shows photo A as its portrait. The master asks for the Character
    /// package, which carries the portrait photo and the player's folders above it, and imports
    /// it with `updatePlayer(data:policy:)`.
    @Test("Joining: master keeps photo A in B/C when the player's Character with portrait A from D/E is imported")
    func masterKeepsItsFolderForACharacterPortrait() async throws {
        let setup = try await Setup.make()

        try await setup.joinWithCharacterPortrait()

        setup.expectMasterLibraryUnchanged()
    }

    /// The master has never seen photo A: the Character brings it along, and the folders the
    /// player keeps it in are the right place for it.
    @Test("Joining: master files a new portrait photo A in the player's D/E and creates those folders")
    func masterCreatesFoldersForANewPortraitPhoto() async throws {
        let setup = try await Setup.make(masterHasPhoto: false)
        let library = setup.masterLibrary
        #expect(library.itemSync(for: setup.photoId, noGame: true) == nil)
        let (dId, eId) = (try #require(setup.playerFolders.first), try #require(setup.playerFolders.last))

        try await setup.joinWithCharacterPortrait()

        #expect(library.itemSync(for: setup.photoId, noGame: true) != nil, "the portrait photo came along")
        #expect(Self.path(of: setup.photoId, in: library) == ["D", "E"])
        #expect(library.itemSync(for: setup.photoId, noGame: true)?.parentId == eId)
        #expect(library.itemSync(for: eId, noGame: true)?.parentId == dId)
        #expect(library.itemSync(for: dId, noGame: true)?.parentId == nil)
        #expect(library.itemSync(for: dId, noGame: true)?.entries.map(\.childId) == [eId])
        #expect(library.itemSync(for: eId, noGame: true)?.entries.map(\.childId) == [setup.photoId])
        #expect(Self.folderIds(in: library) == [dId, eId], "no folder besides the player's own path")
    }
}

private extension PlayerPhotoFolderPlacementTests {
    /// Master and player 1 with the same photo A: in `B/C` on the master, in `D/E` on the player.
    @MainActor
    struct Setup {
        let env: MultiConnectionTestEnvironment
        let photoId: UUID
        let masterFolders: [UUID]
        let playerFolders: [UUID]
        let masterFolderIdsBefore: Set<UUID>
        let masterItemIdsBefore: Set<UUID>
        let masterEntriesBefore: [UUID: Set<UUID>]

        var masterLibrary: PhotoRPG.ItemController { env.masterRoot.photoRoot.itemController }

        /// - Parameter masterHasPhoto: `false` leaves the master's library without any photo.
        static func make(masterHasPhoto: Bool = true) async throws -> Setup {
            let env = try await MultiConnectionTestEnvironment.create()
            for root in masterHasPhoto ? [env.masterRoot, env.player1Root] : [env.player1Root] {
                try await MockRoot.importTestData(
                    into: root.adventureRoot,
                    name: ResourcesDebug.photoTestData,
                    itemCounter: 0
                )
            }
            let masterLibrary = env.masterRoot.photoRoot.itemController
            let playerLibrary = env.player1Root.photoRoot.itemController
            let photoId = try #require(playerLibrary.itemDataModel.items.first {
                playerLibrary.itemSync(for: $0, noGame: true)?.isFolder == false
            })
            if masterHasPhoto {
                try #require(masterLibrary.itemSync(for: photoId, noGame: true) != nil)
            }

            let masterFolders = masterHasPhoto
                ? await PlayerPhotoFolderPlacementTests.file(photoId, in: ["B", "C"], of: env.masterRoot)
                : []
            let playerFolders = await PlayerPhotoFolderPlacementTests.file(photoId, in: ["D", "E"], of: env.player1Root)
            if masterHasPhoto {
                #expect(PlayerPhotoFolderPlacementTests.path(of: photoId, in: masterLibrary) == ["B", "C"])
            }
            #expect(PlayerPhotoFolderPlacementTests.path(of: photoId, in: playerLibrary) == ["D", "E"])

            env.masterRoot.adventureRoot.startGame()
            return Setup(
                env: env,
                photoId: photoId,
                masterFolders: masterFolders,
                playerFolders: playerFolders,
                masterFolderIdsBefore: PlayerPhotoFolderPlacementTests.folderIds(in: masterLibrary),
                masterItemIdsBefore: Set(masterLibrary.itemDataModel.items),
                masterEntriesBefore: PlayerPhotoFolderPlacementTests.entryChildIds(in: masterLibrary)
            )
        }

        /// The player's Character uses photo A as its portrait and joins: it announces the
        /// Character, the master asks for the package and imports what the player answers.
        func joinWithCharacterPortrait() async throws {
            let characterId = UUID()
            env.player1Root.characterRoot.itemController.replace(
                model: ValueModel(id: characterId, name: "Winston", photoId: photoId),
                isInsert: true
            )
            let roster = GameRosterModel(players: [
                PlayerGameModel(id: env.player1Config.id, type: .player, name: "Player - 1", characterId: characterId)
            ])
            env.player1Root.gameModel.reset(gameConfig: env.player1Config, gameRoster: roster)
            env.player1.gameModel.lostMaster = false
            #expect(env.masterRoot.characterRoot.itemController.itemSync(for: characterId, noGame: true) == nil)

            // 1. The player announces the Character by id and version.
            env.playerNetworkSpy.requestHistory.removeAll()
            await env.player1.sendCharacter()
            let announcement = try #require(env.playerNetworkSpy.requestHistory.last as? GameNetworkModel)
            #expect(announcement.data.id == characterId)
            #expect(announcement.data.data == nil)

            // 2. The master does not have that version and asks for the package.
            let request = try #require(try await env.master.handleValue(announcement))
            let askForPackage = env.masterRoot.gameModel.outgoingMessage(
                counter: 1,
                type: .update,
                subType: .store,
                asMaster: true,
                data: request
            )

            // 3. The player answers with the whole Character package.
            env.playerNetworkSpy.requestHistory.removeAll()
            _ = try await env.player1.handleValue(askForPackage)
            let packageMessage = try #require(env.playerNetworkSpy.requestHistory.last as? GameNetworkModel)
            #expect(packageMessage.data.id == characterId)
            #expect(packageMessage.data.data != nil)

            // 4. The master imports it.
            _ = try await env.master.handleValue(packageMessage)
            #expect(
                env.masterRoot.characterRoot.itemController.itemSync(for: characterId, noGame: true) != nil,
                "the Character itself was imported, so the package really went through"
            )
        }

        /// Photo A stays in B/C, the player's folders never reach the master's library, and
        /// nothing else was added, filed twice or moved.
        func expectMasterLibraryUnchanged(sourceLocation: SourceLocation = #_sourceLocation) {
            let library = masterLibrary
            #expect(PlayerPhotoFolderPlacementTests.path(of: photoId, in: library) == ["B", "C"], sourceLocation: sourceLocation)
            #expect(library.itemSync(for: photoId, noGame: true)?.parentId == masterFolders.last, sourceLocation: sourceLocation)
            for playerFolderId in playerFolders {
                #expect(library.itemSync(for: playerFolderId, noGame: true) == nil, sourceLocation: sourceLocation)
            }
            let folderNames = PlayerPhotoFolderPlacementTests.folderIds(in: library)
                .compactMap { library.itemSync(for: $0, noGame: true)?.name }
            #expect(!folderNames.contains("D"), sourceLocation: sourceLocation)
            #expect(!folderNames.contains("E"), sourceLocation: sourceLocation)
            #expect(PlayerPhotoFolderPlacementTests.folderIds(in: library) == masterFolderIdsBefore, sourceLocation: sourceLocation)
            #expect(Set(library.itemDataModel.items) == masterItemIdsBefore, sourceLocation: sourceLocation)
            #expect(PlayerPhotoFolderPlacementTests.entryChildIds(in: library) == masterEntriesBefore, sourceLocation: sourceLocation)
            let foldersListingPhoto = PlayerPhotoFolderPlacementTests.folderIds(in: library).filter { folderId in
                library.itemSync(for: folderId, noGame: true)?.entries.contains { $0.childId == photoId } == true
            }
            #expect(foldersListingPhoto == Set(masterFolders.suffix(1)), sourceLocation: sourceLocation)
        }
    }

    /// Creates the nested folders `names` and files `itemId` in the innermost one.
    /// Returns the folder ids, outermost first.
    ///
    /// The photo is filed in the database only. `EditController.addItem` also moves the photo's
    /// file to the new folder path, and every test root shares one file container: the photo
    /// tests running in parallel (`MultiConnectionPhotoTests`, `SimpleFileFlowTests`,
    /// `PhotoMessageFlowTests`, `PlayerShareReportTests`) then found the shared file gone. The
    /// folders themselves have no file, so they still go through `addItem`.
    static func file(_ itemId: UUID, in names: [String], of root: GameRoot) async -> [UUID] {
        let photoRoot = root.photoRoot
        var folderIds: [UUID] = []
        for name in names {
            let folderId = await photoRoot.itemController.addNew(type: .folder)
            photoRoot.editController.reset(name: name, itemId: folderId)
            if let parentId = folderIds.last {
                photoRoot.editController.addItem(itemId: folderId, parentId: parentId)
            }
            folderIds.append(folderId)
        }
        if let folderId = folderIds.last {
            fileWithoutMovingFile(itemId, into: folderId, of: photoRoot.itemController)
        }
        return folderIds
    }

    /// Makes `folderId` the only folder of `itemId`, like `addItem`, without touching its file.
    static func fileWithoutMovingFile(_ itemId: UUID, into folderId: UUID, of library: PhotoRPG.ItemController) {
        guard let item = library.itemSync(for: itemId, noGame: true)?.copy() else { return }
        if let oldParentId = item.parentId, oldParentId != folderId,
           let oldParent = library.itemSync(for: oldParentId, noGame: true)?.copy() {
            oldParent.entries.removeAll { $0.childId == itemId }
            library.replace(model: oldParent, isInsert: false)
        }
        guard let folder = library.itemSync(for: folderId, noGame: true)?.copy() else { return }
        if !folder.entries.contains(where: { $0.childId == itemId }) {
            folder.entries.append(.newChild(id: itemId))
        }
        item.parentId = folderId
        library.replace(model: folder, isInsert: false)
        library.replace(model: item, isInsert: false)
    }

    /// The names of the folders above `itemId` in the library, outermost first.
    static func path(of itemId: UUID, in library: PhotoRPG.ItemController) -> [String] {
        var names: [String] = []
        var current = library.itemSync(for: itemId, noGame: true)?.parentId
        while let parentId = current, let folder = library.itemSync(for: parentId, noGame: true) {
            names.insert(folder.name, at: 0)
            current = folder.parentId
        }
        return names
    }

    static func folderIds(in library: PhotoRPG.ItemController) -> Set<UUID> {
        Set(library.itemDataModel.items.filter { library.itemSync(for: $0, noGame: true)?.isFolder == true })
    }

    /// Every folder with the ids of its members, to see that no entry was added or moved.
    static func entryChildIds(in library: PhotoRPG.ItemController) -> [UUID: Set<UUID>] {
        var result: [UUID: Set<UUID>] = [:]
        for id in library.itemDataModel.items {
            guard let item = library.itemSync(for: id, noGame: true), item.isFolder else { continue }
            result[id] = Set(item.entries.map(\.childId))
        }
        return result
    }
}
#endif
