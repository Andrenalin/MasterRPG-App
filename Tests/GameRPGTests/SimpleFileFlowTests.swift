// @copyright André Trettin

#if canImport(Testing)
import Foundation
import RPGResourcesDebug
import Testing

@testable import AdventureRPG
@testable import AudioRPG
@testable import CoreRPG
@testable import GameRPG
@testable import MapRPG
@testable import PdfRPG
@testable import PhotoRPG
@testable import SpaceRPG

/// The file-backed modules whose players report what they hold.
enum ReportedFileModule: CaseIterable, Sendable, CustomTestStringConvertible {
    case photo
    case pdf
    case space

    var testDescription: String {
        switch self {
        case .photo: "Photo"
        case .pdf: "Pdf"
        case .space: "Space"
        }
    }

    var fixture: String {
        switch self {
        case .photo: ResourcesDebug.photoTestData
        case .pdf: ResourcesDebug.pdfTestData
        case .space: ResourcesDebug.spaceTestData
        }
    }

    var type: NetworkModules {
        switch self {
        case .photo: .photo
        case .pdf: .pdf
        case .space: .space
        }
    }

    @MainActor
    func controllable(in root: GameRoot) -> any GameControllable {
        switch self {
        case .photo: root.photoRoot.gameControllable
        case .pdf: root.pdfRoot.gameControllable
        case .space: root.spaceRoot.gameControllable
        }
    }

    /// The first item of the module that has a file.
    @MainActor
    func fileItemId(in root: GameRoot) throws -> UUID {
        let items = controllable(in: root).itemControllable
        let itemIds = items.itemDataModel.items
        // The Space fixture's object has no file; its package is the item alone.
        return try #require(itemIds.first { items.itemSync(for: $0)?.fileUrl != nil } ?? itemIds.first)
    }
}

/// One flow for every file-backed module: the game master names the item, a player that lacks
/// it gets its bytes, on its own connection only.
@Suite("Simple file flow", .serialized)
@MainActor
struct SimpleFileFlowTests {
    // MARK: - Photo, Pdf, Space

    @Test("Players that hold the item get its reference only", arguments: ReportedFileModule.allCases)
    func everyoneHoldsTheItem(module: ReportedFileModule) async throws {
        // Given
        let env = try await Self.environment(module: module, holders: [true, true])
        let itemId = try module.fileItemId(in: env.masterRoot)

        // When
        await env.master.show(for: await module.controllable(in: env.masterRoot).share(id: itemId))

        // Then: nobody got bytes and nobody asked for them.
        #expect(Self.packages(of: itemId, in: env).isEmpty)
        #expect(!env.playerSends.contains { $0.message.isAssetRequest })
        for player in env.players {
            #expect(player.controller.gameModel.gameUpdateType == module.type)
            #expect(await module.controllable(in: player.root).currentId == itemId)
            #expect(Self.acknowledged(itemId, by: player, in: env))
        }
    }

    @Test("Only the player that reported no copy gets the bytes", arguments: ReportedFileModule.allCases)
    func reportedMissingPlayerGetsTheBytes(module: ReportedFileModule) async throws {
        // Given: the second player joined without the item.
        let env = try await Self.environment(module: module, holders: [true, false])
        let holder = env.players[0]
        let missing = env.players[1]
        let itemId = try module.fileItemId(in: env.masterRoot)

        // When
        await env.master.show(for: await module.controllable(in: env.masterRoot).share(id: itemId))

        // Then: one package, on the connection of the player that lacks the item.
        let packages = Self.packages(of: itemId, in: env)
        #expect(packages.count == 1)
        #expect(packages.first?.connectionId == missing.connectionId)
        #expect(packages.first?.message.type == .reveal)
        #expect(!packages.contains { $0.connectionId == nil || $0.connectionId == holder.connectionId })
        // The master knew, so the player did not have to ask.
        #expect(!env.playerSends.contains { $0.message.isAssetRequest })

        // And both show it.
        for player in env.players {
            #expect(player.controller.gameModel.gameUpdateType == module.type)
            #expect(await module.controllable(in: player.root).currentId == itemId)
            #expect(Self.acknowledged(itemId, by: player, in: env))
        }
        #expect(await module.controllable(in: missing.root).hasLocalFileData(for: itemId))
    }

    @Test(
        "A player the master did not know to lack the item asks with the counter of the show",
        arguments: ReportedFileModule.allCases
    )
    func unknownMissingPlayerAsksWithTheSameCounter(module: ReportedFileModule) async throws {
        // Given: both players reported the item, and the second one lost it afterwards.
        let env = try await Self.environment(module: module, holders: [true, true])
        let holder = env.players[0]
        let lost = env.players[1]
        let itemId = try module.fileItemId(in: env.masterRoot)
        let lostItems = module.controllable(in: lost.root)
        lostItems.itemControllable.itemDataModel.resetModel(id: itemId)
        lostItems.gameModel.itemData[itemId] = nil
        lostItems.gameModel.items.removeAll { $0 == itemId }

        // When
        await env.master.show(for: await module.controllable(in: env.masterRoot).share(id: itemId))
        // The master's answer to the player's request is queued behind the player's echo.
        await env.settle()

        // Then: the reference went to everyone and the player echoed it without bytes.
        let reference = try #require(env.masterSends.first { $0.message.type == .reveal && $0.message.data.id == itemId })
        #expect(reference.connectionId == nil)
        #expect(reference.message.data.data == nil)
        let request = try #require(env.playerSends.first { $0.message.isAssetRequest })
        #expect(request.connectionId == lost.connectionId)
        #expect(request.message.counter == reference.message.counter)
        #expect(request.message.type == .reveal)
        #expect(request.message.subType == .show)
        #expect(request.message.data.id == itemId)

        // And the master answered on that connection only, under the same counter.
        let packages = Self.packages(of: itemId, in: env)
        #expect(packages.count == 1)
        #expect(packages.first?.connectionId == lost.connectionId)
        #expect(packages.first?.message.counter == reference.message.counter)
        #expect(packages.first?.message.targetId == nil)
        #expect(lost.controller.gameModel.gameUpdateType == module.type)
        #expect(await module.controllable(in: lost.root).currentId == itemId)
        #expect(holder.controller.gameModel.gameUpdateType == module.type)
    }

    @Test("A package of an earlier show is kept but does not replace what is shown now")
    func latePackageDoesNotChangeTheScreen() async throws {
        // Given: a player without photos and two packages of the master.
        let env = try await Self.environment(module: .photo, holders: [false])
        let player = env.players[0]
        let photoIds = env.masterRoot.photoRoot.itemController.itemDataModel.items.filter {
            env.masterRoot.photoRoot.itemController.itemSync(for: $0)?.fileUrl != nil
        }
        try #require(photoIds.count >= 2)
        let earlier = try await env.masterRoot.photoRoot.gameControllable.createGameData(for: photoIds[0])
        let later = try await env.masterRoot.photoRoot.gameControllable.createGameData(for: photoIds[1])
        func reveal(_ data: NetworkCodableDataType, counter: Int) -> GameNetworkModel {
            env.masterRoot.gameModel.outgoingMessage(
                counter: counter,
                type: .reveal,
                subType: .show,
                asMaster: true,
                data: data
            )
        }

        // When: the package of show 40 arrives after the one of show 41.
        await player.controller.received(reveal(later, counter: 41))
        await player.controller.received(reveal(earlier, counter: 40))

        // Then: the later show stays on screen and the earlier photo is there for later.
        #expect(player.root.photoRoot.gameControllable.gameModel.currentItemId == photoIds[1])
        #expect(player.root.photoRoot.photoGameControllable.presentedPhotoId == photoIds[1])
        #expect(await player.root.photoRoot.gameControllable.hasLocalFileData(for: photoIds[0]))
        #expect(await player.root.photoRoot.gameControllable.hasItem(id: photoIds[0], version: earlier.version))
    }

    @Test("A late reference of an earlier show is ignored")
    func lateReferenceDoesNotChangeTheScreen() async throws {
        // Given
        let env = try await Self.environment(module: .photo, holders: [true])
        let player = env.players[0]
        let photoIds = env.masterRoot.photoRoot.itemController.itemDataModel.items.filter {
            env.masterRoot.photoRoot.itemController.itemSync(for: $0)?.fileUrl != nil
        }
        try #require(photoIds.count >= 2)
        func reveal(_ id: UUID, counter: Int) async -> GameNetworkModel {
            env.masterRoot.gameModel.outgoingMessage(
                counter: counter,
                type: .reveal,
                subType: .show,
                asMaster: true,
                data: await env.masterRoot.photoRoot.gameControllable.share(id: id)
            )
        }

        // When
        await player.controller.received(await reveal(photoIds[1], counter: 41))
        await player.controller.received(await reveal(photoIds[0], counter: 40))

        // Then
        #expect(player.root.photoRoot.gameControllable.gameModel.currentItemId == photoIds[1])
    }

    @Test("A photo the master cannot read is asked for once and never sent")
    func unreadableMasterFileEndsAfterOneRequest() async throws {
        // Given: the master's own file is not on its device (an iCloud file that has not
        // downloaded, for example), and the player has no copy.
        let env = try await Self.environment(module: .photo, holders: [false])
        let player = env.players[0]
        let photoId = try ReportedFileModule.photo.fileItemId(in: env.masterRoot)
        let photo = env.masterRoot.photoRoot.itemController.itemOrEmpty(for: photoId)
        let file = try #require(photo.fileUrl)
        photo.fileUrl = FileUrl(
            fileId: file.fileId,
            url: URL(filePath: "/missing/master-photo.png"),
            location: file.location,
            module: file.module,
            relativeUrl: nil,
            contentHash: file.contentHash
        )
        #expect(await !env.masterRoot.photoRoot.gameControllable.hasLocalFileData(for: photoId))

        // When: the photo is shown, and asked for the way a map asks for a pin photo.
        await env.master.show(for: await env.masterRoot.photoRoot.gameControllable.share(id: photoId))
        await player.controller.send(
            counter: 0,
            type: .store,
            subType: .store,
            updated: NetworkCodableDataType(id: photoId, type: .photo, version: photo.version),
            relayToProxyClients: false
        )

        await env.settle()

        // Then: the exchange ended. The player asked once per message and got no package.
        let requests = env.playerSends.filter { $0.message.isAssetRequest && $0.message.data.id == photoId }
        #expect(requests.count == 2)
        #expect(Self.packages(of: photoId, in: env).isEmpty)
        // And the master answered each request with a failure, to that player only, so the
        // player does not wait for bytes that never come (CODE_AUDIT_Game_Shareplay §5.5).
        let failures = env.masterSends.filter {
            $0.message.subType == .failed && $0.message.data.id == photoId
        }
        #expect(failures.count == 2)
        #expect(failures.allSatisfy { $0.connectionId == player.connectionId })
        #expect(failures.first?.message.counter == requests.first?.message.counter)
        #expect(player.controller.gameModel.gameUpdateType != .photo)
    }

    @Test("A package without its file is answered with a failure, not with another request")
    func packageWithoutFileIsNotRequestedAgain() async throws {
        // Given: a package that was exported while the master could not read the file.
        let env = try await Self.environment(module: .photo, holders: [false])
        let player = env.players[0]
        let photoId = try ReportedFileModule.photo.fileItemId(in: env.masterRoot)
        let photo = env.masterRoot.photoRoot.itemController.itemOrEmpty(for: photoId)
        let file = try #require(photo.fileUrl)
        photo.fileUrl = FileUrl(
            fileId: file.fileId,
            url: URL(filePath: "/missing/master-photo.png"),
            location: file.location,
            module: file.module,
            relativeUrl: nil,
            contentHash: file.contentHash
        )
        let package = try await env.masterRoot.photoRoot.gameControllable.createGameData(for: photoId)
        let store = env.masterRoot.gameModel.outgoingMessage(
            counter: 0,
            type: .store,
            subType: .store,
            asMaster: true,
            data: package
        )

        // When
        await player.controller.received(store)

        // Then
        let answers = env.playerSends.filter { $0.message.data.id == photoId }
        #expect(answers.count == 1)
        #expect(answers.first?.message.subType == .failed)
        #expect(!env.playerSends.contains { $0.message.isAssetRequest })
    }

    // MARK: - A player shares

    @Test("A player names an item the master holds; the master shows its own copy", arguments: ReportedFileModule.allCases)
    func playerSharesAnItemTheMasterHolds(module: ReportedFileModule) async throws {
        // Given: the sharing player and the master hold it, the other player does not.
        let env = try await Self.environment(module: module, holders: [true, false])
        let sharer = env.players[0]
        let other = env.players[1]
        let itemId = try module.fileItemId(in: sharer.root)
        let package = try await module.controllable(in: sharer.root).createGameData(for: itemId)

        // When
        await sharer.controller.game(message: package, actionType: .generic)

        // Then: the player sent no bytes.
        let share = try #require(env.playerSends.first { $0.message.type == .update && $0.message.subType == .generic })
        #expect(share.connectionId == sharer.connectionId)
        #expect(share.message.data.id == itemId)
        #expect(share.message.data.data == nil)

        // And the master showed the item like one of its own.
        let packages = Self.packages(of: itemId, in: env)
        #expect(packages.count == 1)
        #expect(packages.first?.connectionId == other.connectionId)
        #expect(packages.first?.message.sender.isMaster == true)
        for player in env.players {
            #expect(player.controller.gameModel.gameUpdateType == module.type)
            #expect(await module.controllable(in: player.root).currentId == itemId)
        }
    }

    @Test("A player contributes an item the master lacks; the master adopts and shows it", arguments: ReportedFileModule.allCases)
    func playerContributesAnItemTheMasterLacks(module: ReportedFileModule) async throws {
        // Given: only the first player holds the item.
        let env = try await Self.environment(module: module, masterHolds: false, holders: [true, false])
        let sharer = env.players[0]
        let other = env.players[1]
        let itemId = try module.fileItemId(in: sharer.root)
        let package = try await module.controllable(in: sharer.root).createGameData(for: itemId)

        // When
        await sharer.controller.game(message: package, actionType: .generic)

        // Then: the bytes went to the master.
        let share = try #require(env.playerSends.first { $0.message.type == .update && $0.message.subType == .generic })
        #expect(share.message.data.data != nil)
        #expect(await module.controllable(in: env.masterRoot).itemControllable.item(for: itemId) != nil)

        // And the master showed its new copy to the player that lacks it.
        let packages = Self.packages(of: itemId, in: env)
        #expect(packages.count == 1)
        #expect(packages.first?.connectionId == other.connectionId)
        #expect(other.controller.gameModel.gameUpdateType == module.type)
        #expect(await module.controllable(in: other.root).hasLocalFileData(for: itemId))
    }

    // MARK: - Audio

    @Test("Audio plays once the player that lacked it has stored it")
    func audioIsDeliveredBeforeItPlays() async throws {
        // Given
        let env = try await LinkedGameEnvironment.create()
        try await env.importData(named: ResourcesDebug.audioTestData, into: env.masterRoot)
        env.masterRoot.adventureRoot.startGame()
        let holder = try await env.addPlayer(named: "Holder")
        try await env.importData(named: ResourcesDebug.audioTestData, into: holder.root)
        holder.root.adventureRoot.startGame()
        let missing = try await env.addPlayer(named: "Missing")
        missing.root.adventureRoot.startGame()
        await env.ready(holder)
        await env.ready(missing)
        env.clearHistory()
        let audioId = try #require(env.masterRoot.audioRoot.itemController.itemDataModel.items.last)

        // When
        await env.master.game(
            message: env.masterRoot.audioRoot.gameController.requestPlay(id: audioId),
            actionType: .playAudio
        )
        await env.master.waitForAudioDeliveries()

        // Then: the file went to the player that lacked it, as a store that shows nothing.
        let packages = env.masterSends.filter { $0.message.data.data != nil && $0.message.data.type == .audio && $0.message.type == .store }
        #expect(packages.count == 1)
        #expect(packages.first?.connectionId == missing.connectionId)
        #expect(await missing.root.audioRoot.audioGameControllable.hasLocalFileData(for: audioId))

        // And its acknowledgement started the playback for everyone.
        let play = env.masterSends.filter { $0.message.subType == .playAudio }
        #expect(play.count == 1)
        #expect(play.first?.connectionId == nil)
        #expect(env.master.gameModel.pendingAudioPlays[audioId] == nil)
    }

    @Test("A pending audio play starts for the ready players after its deadline, a late player joins it (§5.7)")
    func pendingAudioPlayHasADeadline() async throws {
        // Given: one player that answers and one that never does.
        let env = try await LinkedGameEnvironment.create()
        try await env.importData(named: ResourcesDebug.audioTestData, into: env.masterRoot)
        env.masterRoot.adventureRoot.startGame()
        let ready = try await env.addPlayer(named: "Ready")
        try await env.importData(named: ResourcesDebug.audioTestData, into: ready.root)
        ready.root.adventureRoot.startGame()
        let quiet = try await env.addPlayer(named: "Quiet")
        quiet.root.adventureRoot.startGame()
        await env.ready(ready)
        await env.ready(quiet)
        env.mute(quiet)
        env.clearHistory()
        env.master.audioPlayDeadline = .seconds(2)
        let audioId = try #require(env.masterRoot.audioRoot.itemController.itemDataModel.items.last)

        // When
        await env.master.game(
            message: env.masterRoot.audioRoot.gameController.requestPlay(id: audioId),
            actionType: .playAudio
        )
        await env.master.waitForAudioDeliveries()

        // Then: the quiet player blocks the play until the deadline, then it starts for all.
        #expect(env.masterSends.filter { $0.message.subType == .playAudio }.isEmpty)
        let deadline = ContinuousClock.now + .seconds(5)
        while env.master.runningAudioPlay == nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(env.master.runningAudioPlay != nil)
        let plays = env.masterSends.filter { $0.message.subType == .playAudio }
        #expect(plays.count == 1)
        #expect(plays.first?.connectionId == nil)
        #expect(env.master.gameModel.pendingAudioPlays[audioId] == nil)
        #expect(env.master.audioPlayDeadlineTasks.isEmpty)

        // And the player joins the running play once it has the file.
        env.unmute(quiet)
        try await env.importData(named: ResourcesDebug.audioTestData, into: quiet.root)
        env.clearHistory()
        await env.ready(quiet)
        await env.settle()
        let joins = env.masterSends.filter { $0.message.subType == .playAudio }
        #expect(joins.count == 1)
        #expect(joins.first?.connectionId == quiet.connectionId)
    }

    @Test("A receipt whose log row was evicted still completes the delivery (§5.8)")
    func receiptCountsAfterTheLogRowIsEvicted() async throws {
        // Given: a play waits for a player; its package was sent but not delivered yet.
        let env = try await LinkedGameEnvironment.create()
        try await env.importData(named: ResourcesDebug.audioTestData, into: env.masterRoot)
        env.masterRoot.adventureRoot.startGame()
        let missing = try await env.addPlayer(named: "Missing")
        missing.root.adventureRoot.startGame()
        await env.ready(missing)
        env.mute(missing)
        env.clearHistory()
        let audioId = try #require(env.masterRoot.audioRoot.itemController.itemDataModel.items.last)
        await env.master.game(
            message: env.masterRoot.audioRoot.gameController.requestPlay(id: audioId),
            actionType: .playAudio
        )
        await env.master.waitForAudioDeliveries()
        let package = try #require(env.masterSends.map(\.message).first { $0.type == .store && $0.data.data != nil })
        #expect(env.master.gameModel.pendingAudioPlays[audioId] != nil)

        // When: the display log forgets every row before the receipt arrives.
        env.masterRoot.gameModel.logs.removeAll()
        env.masterRoot.gameModel.logData.removeAll()
        env.unmute(missing)
        await missing.controller.receivedProcess(package)
        await env.settle()

        // Then: the receipt was still matched, so the play started.
        #expect(env.master.gameModel.pendingAudioPlays[audioId] == nil)
        #expect(env.masterSends.contains { $0.message.subType == .playAudio })
    }

    @Test("A pause cancels the deadline of a pending audio play")
    func pauseCancelsTheAudioPlayDeadline() async throws {
        let env = try await LinkedGameEnvironment.create()
        try await env.importData(named: ResourcesDebug.audioTestData, into: env.masterRoot)
        env.masterRoot.adventureRoot.startGame()
        let quiet = try await env.addPlayer(named: "Quiet")
        quiet.root.adventureRoot.startGame()
        await env.ready(quiet)
        env.mute(quiet)
        env.master.audioPlayDeadline = .seconds(30)
        let audioId = try #require(env.masterRoot.audioRoot.itemController.itemDataModel.items.last)

        await env.master.game(
            message: env.masterRoot.audioRoot.gameController.requestPlay(id: audioId),
            actionType: .playAudio
        )
        await env.master.waitForAudioDeliveries()
        #expect(env.master.audioPlayDeadlineTasks.count == 1)

        let pause = AudioPlayRequest(id: audioId, shouldPlay: false).command
        await env.master.requestAudioPlay(pause)

        #expect(env.master.audioPlayDeadlineTasks.isEmpty)
        #expect(env.master.runningAudioPlay == nil)
    }

    @Test("A player that holds an audio skips the Journal copy, one that lacks it loads it")
    func journalCopyIsSkippedOnlyWhereTheFileIsHeld() async throws {
        // Given: one player imported the audio, the other did not.
        let env = try await LinkedGameEnvironment.create()
        try await env.importData(named: ResourcesDebug.audioTestData, into: env.masterRoot)
        env.masterRoot.adventureRoot.startGame()
        let holder = try await env.addPlayer(named: "Holder")
        try await env.importData(named: ResourcesDebug.audioTestData, into: holder.root)
        holder.root.adventureRoot.startGame()
        let missing = try await env.addPlayer(named: "Missing")
        missing.root.adventureRoot.startGame()
        await env.ready(holder)
        await env.ready(missing)
        let audioId = try #require(env.masterRoot.audioRoot.itemController.itemDataModel.items.last)
        let reference = await env.masterRoot.audioRoot.gameControllable.share(id: audioId)
        let message = env.master.outgoingMessage(type: .store, subtype: .show, updated: reference)

        // Then: the holder skips the download, the player without the file loads it.
        #expect(await holder.controller.sharePlayHoldsFile(message))
        #expect(await !missing.controller.sharePlayHoldsFile(message))

        // And a message that is not the game master's is never skipped.
        var fromPlayer = message
        fromPlayer.sender.role = .player
        #expect(await !holder.controller.sharePlayHoldsFile(fromPlayer))
    }

    // MARK: - Map

    @Test("A player without the map asks for it and gets the package with the live state")
    func mapIsDeliveredOnRequest() async throws {
        // Given: Map players report nothing, so the master names the map.
        let env = try await LinkedGameEnvironment.create()
        try await env.importData(named: ResourcesDebug.adventureTestData, into: env.masterRoot)
        env.masterRoot.adventureRoot.startGame()
        let holder = try await env.addPlayer(named: "Holder")
        try await env.importData(named: ResourcesDebug.adventureTestData, into: holder.root)
        holder.root.adventureRoot.startGame()
        let missing = try await env.addPlayer(named: "Missing")
        missing.root.adventureRoot.startGame()
        await env.ready(holder)
        await env.ready(missing)
        let mapId = try #require(env.masterRoot.mapRoot.itemController.itemDataModel.items.first)
        _ = await env.masterRoot.mapRoot.gameController.setCurrent(itemId: mapId)
        env.masterRoot.mapRoot.rootModel.isMapStreaming = true
        env.clearHistory()

        // When
        await env.master.show(for: await env.masterRoot.mapRoot.mapGameControllable.shareMap(id: mapId))

        // Then: the reference went to everyone; only the player without the map asked.
        let reference = try #require(env.masterSends.first { $0.message.type == .reveal && $0.message.data.id == mapId })
        #expect(reference.connectionId == nil)
        #expect(reference.message.data.data == nil)
        let requests = env.playerSends.filter { $0.message.isAssetRequest && $0.message.data.type == .map }
        #expect(requests.count == 1)
        #expect(requests.first?.connectionId == missing.connectionId)
        #expect(requests.first?.message.counter == reference.message.counter)

        // And it got the package on its connection, followed by content and state.
        let packages = env.masterSends.filter { $0.message.type == .reveal && $0.message.data.data != nil }
        #expect(packages.count == 1)
        #expect(packages.first?.connectionId == missing.connectionId)
        #expect(packages.first?.message.counter == reference.message.counter)
        let followUps = env.masterSends.filter { $0.connectionId == missing.connectionId && $0.message.type == .update }
        #expect(followUps.contains { $0.message.subType == .generic && $0.message.data.type == .map })
        #expect(followUps.contains { $0.message.subType == .mapState })

        // And both show the map.
        for player in env.players {
            #expect(player.controller.gameModel.gameUpdateType == .map)
            #expect(player.root.mapRoot.gameControllable.gameModel.currentItemId == mapId)
        }
    }

    @Test("The map package is shown although the state of that map arrived before it")
    func mapPackageArrivesAfterItsState() async throws {
        // Given: a player without the map. On a real network the content and the state that
        // follow the reveal overtake the package the player asks for.
        let env = try await LinkedGameEnvironment.create()
        try await env.importData(named: ResourcesDebug.adventureTestData, into: env.masterRoot)
        env.masterRoot.adventureRoot.startGame()
        let player = try await env.addPlayer(named: "Missing")
        player.root.adventureRoot.startGame()
        await env.ready(player)
        let mapId = try #require(env.masterRoot.mapRoot.itemController.itemDataModel.items.first)
        _ = await env.masterRoot.mapRoot.gameController.setCurrent(itemId: mapId)
        // The linked master would answer the request at once. Share Map is paused so that it
        // stays silent and the test delivers the messages in the order of a real network.
        env.masterRoot.mapRoot.rootModel.isMapStreaming = false
        let map = env.masterRoot.mapRoot.mapGameControllable
        func message(_ counter: Int, _ type: RPGMessageType, _ subType: RPGMessageActionType, _ data: NetworkCodableDataType) -> GameNetworkModel {
            env.masterRoot.gameModel.outgoingMessage(counter: counter, type: type, subType: subType, asMaster: true, data: data)
        }
        let reference = await map.shareMap(id: mapId)
        let package = try await map.createMapGameData(for: mapId)
        let content = await map.networkMapContentUpdate(for: mapId)
        let state = map.networkMapUpdate(for: mapId)
        env.clearHistory()

        // When
        await player.controller.received(message(30, .reveal, .show, reference))
        await player.controller.received(message(31, .update, .generic, content))
        await player.controller.received(message(32, .update, .mapState, state))
        await player.controller.received(message(30, .reveal, .show, package))

        // Then: the player asked once, and the package of show 30 is shown.
        #expect(env.masterSends.allSatisfy { $0.message.data.id != mapId })
        let answers = env.playerSends.filter { $0.message.data.id == mapId }.map(\.message)
        #expect(answers.filter(\.isAssetRequest).count == 1)
        #expect(answers.last?.type == .reveal)
        #expect(answers.last?.subType == .ok)
        #expect(answers.last?.counter == 30)
        #expect(player.controller.gameModel.gameUpdateType == .map)
        #expect(player.root.mapRoot.gameControllable.gameModel.currentItemId == mapId)
    }

    @Test("The package of a map is kept but not shown once something else was shown")
    func lateMapPackageDoesNotReplaceALaterPhoto() async throws {
        // Given
        let env = try await LinkedGameEnvironment.create()
        try await env.importData(named: ResourcesDebug.adventureTestData, into: env.masterRoot)
        try await env.importData(named: ResourcesDebug.photoTestData, into: env.masterRoot)
        env.masterRoot.adventureRoot.startGame()
        let player = try await env.addPlayer(named: "Missing")
        try await env.importData(named: ResourcesDebug.photoTestData, into: player.root)
        player.root.adventureRoot.startGame()
        await env.ready(player)
        let mapId = try #require(env.masterRoot.mapRoot.itemController.itemDataModel.items.first)
        let photoId = try ReportedFileModule.photo.fileItemId(in: player.root)
        // Share Map is paused so that the linked master does not answer the request itself.
        env.masterRoot.mapRoot.rootModel.isMapStreaming = false
        let map = env.masterRoot.mapRoot.mapGameControllable
        func message(_ counter: Int, _ data: NetworkCodableDataType) -> GameNetworkModel {
            env.masterRoot.gameModel.outgoingMessage(counter: counter, type: .reveal, subType: .show, asMaster: true, data: data)
        }
        let mapReference = await map.shareMap(id: mapId)
        let mapPackage = try await map.createMapGameData(for: mapId)
        let photoReference = await env.masterRoot.photoRoot.gameControllable.share(id: photoId)

        // When: the map is shown, then a photo, and only then the map package arrives.
        await player.controller.received(message(30, mapReference))
        await player.controller.received(message(31, photoReference))
        await player.controller.received(message(30, mapPackage))

        // Then
        #expect(env.masterSends.allSatisfy { $0.message.data.id != mapId })
        #expect(player.controller.gameModel.gameUpdateType == .photo)
        #expect(await player.root.mapRoot.gameControllable.hasItem(id: mapId, version: 0))
    }

    @Test("A paused Share Map keeps the map from a player that asks for it")
    func pausedMapSharingAnswersNoRequest() async throws {
        // Given
        let env = try await LinkedGameEnvironment.create()
        try await env.importData(named: ResourcesDebug.adventureTestData, into: env.masterRoot)
        env.masterRoot.adventureRoot.startGame()
        let missing = try await env.addPlayer(named: "Missing")
        missing.root.adventureRoot.startGame()
        await env.ready(missing)
        let mapId = try #require(env.masterRoot.mapRoot.itemController.itemDataModel.items.first)
        _ = await env.masterRoot.mapRoot.gameController.setCurrent(itemId: mapId)
        env.masterRoot.mapRoot.rootModel.isMapStreaming = false
        env.clearHistory()

        // When
        await env.master.show(for: await env.masterRoot.mapRoot.mapGameControllable.shareMap(id: mapId))

        // Then: the player asked, and nothing but the reference left the master.
        #expect(env.playerSends.contains { $0.message.isAssetRequest && $0.message.data.id == mapId })
        #expect(Self.packages(of: mapId, in: env).isEmpty)
        #expect(!env.masterSends.contains { $0.message.type == .update && $0.message.data.type == .map })
        #expect(missing.controller.gameModel.gameUpdateType != .map)
        #expect(env.masterRoot.mapRoot.rootModel.mapsWithUnsharedStructure.contains(mapId))
    }
}

private extension SimpleFileFlowTests {
    /// A master and one player per entry of `holders`. A player whose entry is `true` joined
    /// with the fixture of `module` in its library. Every player did the connect handshake,
    /// which is what tells the master what it holds.
    static func environment(
        module: ReportedFileModule,
        masterHolds: Bool = true,
        holders: [Bool]
    ) async throws -> LinkedGameEnvironment {
        let env = try await LinkedGameEnvironment.create()
        if masterHolds {
            try await env.importData(named: module.fixture, into: env.masterRoot)
        }
        env.masterRoot.adventureRoot.startGame()

        for (index, holds) in holders.enumerated() {
            let player = try await env.addPlayer(named: "Player \(index + 1)")
            if holds {
                try await env.importData(named: module.fixture, into: player.root)
            }
            player.root.adventureRoot.startGame()
        }
        for player in env.players {
            await env.ready(player)
        }
        env.clearHistory()
        return env
    }

    /// The reveals and stores of the master that carried the bytes of the item.
    static func packages(
        of itemId: UUID,
        in env: LinkedGameEnvironment
    ) -> [(connectionId: ConnectionController.ID?, message: GameNetworkModel)] {
        env.masterSends.filter {
            ($0.message.type == .reveal || $0.message.type == .store) &&
                $0.message.data.id == itemId &&
                $0.message.data.data != nil
        }
    }

    /// Whether the player answered a master message about the item with `.ok`.
    static func acknowledged(_ itemId: UUID, by player: LinkedGameEnvironment.Player, in env: LinkedGameEnvironment) -> Bool {
        env.playerSends.contains {
            $0.connectionId == player.connectionId &&
                $0.message.subType == .ok &&
                $0.message.data.id == itemId
        }
    }
}
#endif
