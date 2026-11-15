// @copyright André Trettin

import CoreRPG
import Foundation
import RPGResourcesDebug
import Testing

@testable import AudioRPG

@MainActor
struct LinkControllerTests {
    @Test func toggleTextLink() async throws {
        let root = try await MockRoot.importTestData()
        
        let sut = root.linkController
        var result = sut.toggleTextLink(linkNumber: 0, itemId: UUID(), entryId: nil, command: nil, in: "", shareResult: nil, toggler: nil, editAction: nil)
        #expect(result.isEmpty)
                
        let firstItem = root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[0])
        let text = sut.generateLink(itemId: firstItem.id)
        result = sut.toggleTextLink(linkNumber: 0, itemId: firstItem.id, entryId: nil, command: nil, in: text, shareResult: nil, toggler: nil, editAction: nil)
        var expectedText = "\(text)➡️[Play](RPG://AUDIOS/200/DEBCC881-3CA8-45C1-9406-14AD506E63BC/play) Rolling 2d20 sound for testing Audio⬅️"
        #expect(result == expectedText)
        
        result = sut.toggleTextLink(linkNumber: LinkType.play.linkNumberAddition, itemId: firstItem.id, entryId: nil, command: LinkType.play.rawValue, in: result, shareResult: nil, toggler: nil, editAction: nil)
        expectedText = "\(text)➡️[Play](RPG://AUDIOS/200/DEBCC881-3CA8-45C1-9406-14AD506E63BC/play)➡️playing⬅️ Rolling 2d20 sound for testing Audio⬅️"
        #expect(result == expectedText)
        
        result = sut.toggleTextLink(linkNumber: LinkType.play.linkNumberAddition, itemId: firstItem.id, entryId: nil, command: LinkType.play.rawValue, in: result, shareResult: nil, toggler: nil, editAction: nil)
        expectedText = "\(text)➡️[Play](RPG://AUDIOS/200/DEBCC881-3CA8-45C1-9406-14AD506E63BC/play)➡️playing⬅️ Rolling 2d20 sound for testing Audio⬅️"
        #expect(result == expectedText)
    }

    @Test func toggleTextLinkAddsShareShowAndRemoveActions() async throws {
        let root = try await MockRoot.importTestData()
        let sut = root.linkController
        let shareResult = ShareValueResult.preview()
        let firstItem = root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[0])
        let link = sut.generateLink(itemId: firstItem.id)

        var text = sut.toggleTextLink(
            linkNumber: 0,
            itemId: firstItem.id,
            entryId: nil,
            command: nil,
            in: link,
            shareResult: shareResult,
            toggler: toggler(),
            editAction: editAction()
        )

        #expect(text.contains("[Share]"))
        #expect(text.contains("[Show]"))
        #expect(text.contains("[Play]"))
        #expect(text.contains("[Remove]"))
        #expect(text.contains(firstItem.description))

        let showText = sut.toggleTextLink(
            linkNumber: LinkType.show.linkNumberAddition,
            itemId: firstItem.id,
            entryId: nil,
            command: LinkType.show.rawValue,
            in: text,
            shareResult: shareResult,
            toggler: toggler(),
            editAction: editAction()
        )
        #expect(showText == text)

        let shareText = sut.toggleTextLink(
            linkNumber: LinkType.share.linkNumberAddition,
            itemId: firstItem.id,
            entryId: nil,
            command: LinkType.share.rawValue,
            in: text,
            shareResult: shareResult,
            toggler: toggler(),
            editAction: editAction()
        )
        #expect(shareText == text)

        text = sut.toggleTextLink(
            linkNumber: LinkType.remove.linkNumberAddition,
            itemId: firstItem.id,
            entryId: nil,
            command: LinkType.remove.rawValue,
            in: text,
            shareResult: shareResult,
            toggler: toggler(),
            editAction: editAction()
        )
        #expect(text == firstItem.name)

        try await Task.sleep(for: .milliseconds(1))
    }

    /// CODE_AUDIT_26 §5.28: the play link of a playlist item loads the playlist's tracks.
    @Test func playLinkOfAPlaylistLoadsItsTracks() async throws {
        let root = try await MockRoot.importTestData()
        let sut = root.linkController
        let source = try #require(root.itemController.itemDataModel.items.first {
            root.itemController.itemSync(for: $0)?.fileUrl != nil
        })
        let fileUrl = try #require(root.itemController.itemSync(for: source)?.fileUrl)
        let audio = try #require(await root.itemController.fileUrlDataController?.loadData(for: fileUrl))

        var trackIds: [UUID] = []
        for number in 1...2 {
            let id = UUID()
            let url = URL.temporaryDirectory.appending(path: "playlist-link-\(id.uuidString).m4a")
            try audio.write(to: url)
            let trackUrl = FileUrl(fileId: id, url: url, location: .local, module: NetworkModules.audio.token, relativeUrl: nil)
            root.itemController.replace(model: AudioModel(id: id, name: "Track \(number)", fileUrl: trackUrl), isInsert: true)
            trackIds.append(id)
        }
        let playlistId = UUID()
        root.itemController.replace(
            model: AudioModel(id: playlistId, name: "Playlist", entries: trackIds.map { AudioEntryModel(id: UUID(), audioId: $0) }),
            isInsert: true
        )
        let link = sut.generateLink(itemId: playlistId)
        let withActions = sut.toggleTextLink(linkNumber: 0, itemId: playlistId, entryId: nil, command: nil, in: link, shareResult: nil, toggler: nil, editAction: nil)

        let result = sut.toggleTextLink(linkNumber: LinkType.play.linkNumberAddition, itemId: playlistId, entryId: nil, command: LinkType.play.rawValue, in: withActions, shareResult: nil, toggler: nil, editAction: nil)
        #expect(result.contains("playing"))

        // The load runs on a task of its own.
        for _ in 0..<100 where root.audioController.model.playList.count < trackIds.count {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(root.audioController.model.playList.map(\.id) == trackIds)
        #expect(root.audioController.model.playListRootId == playlistId)
    }

    private func toggler() -> ((UUID, NetworkModules) async -> Void) {
        { _, _ in }
    }

    private func editAction() -> ((ItemRowModel) -> Bool) {
        { _ in true }
    }
}
