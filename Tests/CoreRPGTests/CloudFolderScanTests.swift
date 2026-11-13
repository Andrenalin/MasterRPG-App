// @copyright André Trettin

import Foundation
import Testing
import UniformTypeIdentifiers

@testable import CoreRPG

/// The scan of a module's iCloud folder for files without an item: listing, ids and planning.
@Suite("Cloud folder scan")
struct CloudFolderScanTests {
    private func file(_ path: String) -> CloudScanFile {
        CloudScanFile(components: path.split(separator: "/").map(String.init))
    }

    private func existing(
        _ name: String,
        id: UUID = UUID(),
        parentId: UUID? = nil,
        isFolder: Bool = false,
        isTrashed: Bool = false,
        file: String? = nil
    ) -> CloudScanExistingItem {
        CloudScanExistingItem(
            id: id, name: name, parentId: parentId, isFolder: isFolder, isTrashed: isTrashed,
            fileComponents: file.map { $0.split(separator: "/").map(String.init) }
        )
    }

    // MARK: - Ids

    @Test("The derived id is a valid UUID and the same on every call")
    func derivedIdIsStable() {
        let first = CloudFolderScan.derivedId(module: "pdf", path: ["Rollenspiel", "00 Pdf.pdf"], isFolder: false)
        let second = CloudFolderScan.derivedId(module: "pdf", path: ["Rollenspiel", "00 Pdf.pdf"], isFolder: false)
        #expect(first == second)
        #expect(first.uuidString.split(separator: "-")[2].hasPrefix("5"), "version 5 bits")
        #expect(UUID(uuidString: first.uuidString) == first)
    }

    @Test("The derived id differs by path, module and kind")
    func derivedIdDiffers() {
        let base = CloudFolderScan.derivedId(module: "pdf", path: ["A", "B.pdf"], isFolder: false)
        #expect(base != CloudFolderScan.derivedId(module: "pdf", path: ["B", "B.pdf"], isFolder: false))
        #expect(base != CloudFolderScan.derivedId(module: "audio", path: ["A", "B.pdf"], isFolder: false))
        #expect(base != CloudFolderScan.derivedId(module: "pdf", path: ["A", "B.pdf"], isFolder: true))
        #expect(CloudFolderScan.derivedId(module: "pdf", path: ["Example", "00 Pdf.pdf"], isFolder: false)
                != CloudFolderScan.derivedId(module: "pdf", path: ["Rollenspiel", "PDFs", "Example", "00 Pdf.pdf"], isFolder: false),
                "the same file name in two folders is two items")
    }

    @Test("A name stored decomposed and precomposed gets one id")
    func derivedIdIgnoresUnicodeForm() {
        let precomposed = "Gr\u{00F6}\u{00DF}e.pdf"
        let decomposed = "Gro\u{0308}\u{00DF}e.pdf"
        #expect(Array(precomposed.utf8) != Array(decomposed.utf8), "different bytes on disk, although Swift calls the strings equal")
        #expect(CloudFolderScan.derivedId(module: "pdf", path: [precomposed], isFolder: false)
                == CloudFolderScan.derivedId(module: "pdf", path: [decomposed], isFolder: false))
    }

    // MARK: - File names

    @Test("A placeholder is listed with its real name and hidden files are skipped")
    func realFileNames() {
        #expect(CloudFolderScan.realFileName(".00 Pdf.pdf.icloud") == "00 Pdf.pdf")
        #expect(CloudFolderScan.realFileName("00 Pdf.pdf") == "00 Pdf.pdf")
        #expect(CloudFolderScan.realFileName(".DS_Store") == nil)
        #expect(CloudFolderScan.realFileName(".icloud") == nil)
    }

    @Test("The item name is the file name without its extension")
    func itemName() {
        #expect(file("A/B/00 Pdf.pdf").itemName == "00 Pdf")
        #expect(file("A/Archive.tar.gz").itemName == "Archive.tar")
        #expect(file("A/B/00 Pdf.pdf").storedUrl.path(percentEncoded: false) == "/A/B/00 Pdf.pdf")
    }

    // MARK: - Listing

    @Test("Listing finds the module's files in folders, placeholders included, and skips the rest")
    func listing() async throws {
        let root = URL.temporaryDirectory.appending(path: "CloudScanListing-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        func write(_ path: String) throws {
            let url = root.appending(path: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("x".utf8).write(to: url)
        }
        try write("Top.pdf")
        try write("Rollenspiel/PDFs/Example/00 Pdf.pdf")
        try write("Rollenspiel/PDFs/Example/.Cloud Only.pdf.icloud")
        try write("Rollenspiel/PDFs/Example/.DS_Store")
        try write("Rollenspiel/notes.txt")
        try write("Rollenspiel/picture.png")
        try write(".hidden/Secret.pdf")

        let found = try #require(await CloudFolderScan.listing(below: root, fileTypes: [.pdf])).files

        #expect(found.map { $0.components.joined(separator: "/") } == [
            "Rollenspiel/PDFs/Example/00 Pdf.pdf",
            "Rollenspiel/PDFs/Example/Cloud Only.pdf",
            "Top.pdf"
        ])
        #expect(found.first { $0.fileName == "Cloud Only.pdf" }?.isPlaceholder == true)
        #expect(found.first { $0.fileName == "Top.pdf" }?.isPlaceholder == false)
    }

    @Test("An unreadable module folder is not the same as a folder without files")
    func listingMissingFolder() async throws {
        let missing = URL.temporaryDirectory.appending(path: "CloudScanMissing-\(UUID().uuidString)")
        #expect(await CloudFolderScan.listing(below: missing, fileTypes: [.pdf]) == nil)

        let empty = URL.temporaryDirectory.appending(path: "CloudScanEmpty-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: empty) }
        #expect(try #require(await CloudFolderScan.listing(below: empty, fileTypes: [.pdf])).files.isEmpty)
    }

    // MARK: - Planning

    @Test("Missing files get their folder chain and an item each, parents before children")
    func planBuildsFolderChain() {
        let plan = CloudFolderScan.plan(
            files: [file("Rollenspiel/PDFs/Example/00 Pdf.pdf"), file("Rollenspiel/PDFs/Other.pdf"), file("Top.pdf")],
            existing: [],
            module: "pdf"
        )

        #expect(plan.folders.map { $0.path.joined(separator: "/") } == ["Rollenspiel", "Rollenspiel/PDFs", "Rollenspiel/PDFs/Example"])
        #expect(plan.items.count == 3)
        let folderIds = Dictionary(uniqueKeysWithValues: plan.folders.map { ($0.path.joined(separator: "/"), $0.id) })
        #expect(plan.folders[0].parentId == nil)
        #expect(plan.folders[1].parentId == folderIds["Rollenspiel"])
        #expect(plan.folders[2].parentId == folderIds["Rollenspiel/PDFs"])
        let deep = plan.items.first { $0.name == "00 Pdf" }
        #expect(deep?.parentId == folderIds["Rollenspiel/PDFs/Example"])
        #expect(plan.items.first { $0.name == "Top" }?.parentId == nil, "a file at the module root has no folder")
    }

    @Test("A file an item references is not added, however the case or Unicode form differs")
    func planSkipsReferencedFiles() {
        let plan = CloudFolderScan.plan(
            files: [file("Folder/Known.pdf"), file("Folder/Gr\u{00F6}\u{00DF}e.pdf"), file("Folder/New.pdf")],
            existing: [
                existing("Known", file: "folder/known.PDF"),
                existing("Gr\u{00F6}\u{00DF}e", file: "Folder/Gro\u{0308}\u{00DF}e.pdf")
            ],
            module: "pdf"
        )

        #expect(plan.items.map(\.name) == ["New"])
    }

    @Test("An existing folder with the same name path is reused and not created again")
    func planReusesExistingFolders() {
        let rollenspiel = existing("Rollenspiel", isFolder: true)
        let pdfs = existing("PDFs", parentId: rollenspiel.id, isFolder: true)
        let plan = CloudFolderScan.plan(
            files: [file("rollenspiel/PDFs/Example/New.pdf")],
            existing: [rollenspiel, pdfs],
            module: "pdf"
        )

        #expect(plan.folders.map(\.name) == ["Example"], "only the missing level is created")
        #expect(plan.folders.first?.parentId == pdfs.id)
        #expect(plan.items.first?.parentId == plan.folders.first?.id)
    }

    @Test("A trashed folder is not reused")
    func planIgnoresTrashedFolders() {
        let trashed = existing("Gone", isFolder: true, isTrashed: true)
        let plan = CloudFolderScan.plan(files: [file("Gone/New.pdf")], existing: [trashed], module: "pdf")

        #expect(plan.folders.count == 1)
        #expect(plan.folders.first?.id != trashed.id)
        #expect(plan.items.first?.parentId == plan.folders.first?.id)
    }

    @Test("A folder below a trashed folder is not reused")
    func planIgnoresFoldersBelowTrash() {
        let trashed = existing("Gone", isFolder: true, isTrashed: true)
        let child = existing("Sub", parentId: trashed.id, isFolder: true)
        let plan = CloudFolderScan.plan(files: [file("Gone/Sub/New.pdf")], existing: [trashed, child], module: "pdf")

        #expect(plan.folders.map(\.name) == ["Gone", "Sub"])
    }

    @Test("Items get the path-derived id, so another device plans the same ids")
    func planUsesDerivedIds() {
        let files = [file("A/B/One.pdf"), file("A/Two.pdf")]
        let first = CloudFolderScan.plan(files: files, existing: [], module: "pdf")
        let second = CloudFolderScan.plan(files: files.reversed(), existing: [], module: "pdf")

        #expect(first == second, "the order of the listing does not matter")
        #expect(first.items.first { $0.name == "One" }?.id == CloudFolderScan.derivedId(module: "pdf", path: ["A", "B", "One.pdf"], isFolder: false))
        #expect(first.folders.first { $0.name == "B" }?.id == CloudFolderScan.derivedId(module: "pdf", path: ["A", "B"], isFolder: true))
    }

    @Test("When the derived id is taken by another item, the new item gets a random id")
    func planAvoidsIdClash() {
        let derived = CloudFolderScan.derivedId(module: "pdf", path: ["Taken.pdf"], isFolder: false)
        let plan = CloudFolderScan.plan(files: [file("Taken.pdf")], existing: [existing("Renamed", id: derived)], module: "pdf")

        #expect(plan.items.count == 1)
        #expect(plan.items.first?.id != derived)
    }

    @Test("The same file listed twice is planned once, and nothing missing gives an empty plan")
    func planDeduplicatesAndCanBeEmpty() {
        let twice = CloudFolderScan.plan(files: [file("A/One.pdf"), file("a/one.pdf")], existing: [], module: "pdf")
        #expect(twice.items.count == 1)

        let folder = existing("A", isFolder: true)
        let none = CloudFolderScan.plan(files: [file("A/One.pdf")], existing: [folder, existing("One", parentId: folder.id, file: "A/One.pdf")], module: "pdf")
        #expect(none.isEmpty)
    }

    // MARK: - Files missing on iCloud

    @Test("An item whose file is gone is offered for removal; trashed and file-less items are not")
    func planFindsMissingFiles() {
        let folder = existing("Folder", isFolder: true)
        let gone = existing("Gone", parentId: folder.id, file: "Folder/Gone.pdf")
        let kept = existing("Kept", parentId: folder.id, file: "Folder/Kept.pdf")
        let trashed = existing("Trashed", parentId: folder.id, isTrashed: true, file: "Folder/Trashed.pdf")
        let plain = existing("No file")
        let plan = CloudFolderScan.plan(files: [file("Folder/Kept.pdf")], existing: [folder, gone, kept, trashed, plain], module: "pdf")

        #expect(plan.removals.map(\.id) == [gone.id])
        #expect(plan.removals.first?.path == ["Folder", "Gone.pdf"])
        #expect(plan.items.isEmpty && plan.moves.isEmpty)
    }

    @Test("Most files missing is flagged, a single missing file is not")
    func planFlagsMostFilesMissing() {
        let items = (0..<5).map { existing("Item \($0)", file: "F/Item \($0).pdf") }
        #expect(CloudFolderScan.plan(files: [], existing: items, module: "pdf").mostFilesMissing)
        #expect(!CloudFolderScan.plan(files: items.dropFirst().map { file($0.fileComponents!.joined(separator: "/")) }, existing: items, module: "pdf").mostFilesMissing)
    }

    // MARK: - Files moved on iCloud

    @Test("A file of the same name in another folder is the item's moved file")
    func planPairsMovedFile() {
        let item = existing("Moved", file: "Old/Moved.pdf")
        let plan = CloudFolderScan.plan(files: [file("New/Deep/Moved.pdf")], existing: [item], module: "pdf")

        #expect(plan.removals.isEmpty, "the item is not removed")
        #expect(plan.items.isEmpty, "the file does not get a second item")
        #expect(plan.folders.map { $0.path.joined(separator: "/") } == ["New", "New/Deep"])
        let move = plan.moves.first
        #expect(plan.moves.count == 1)
        #expect(move?.id == item.id)
        #expect(move?.file?.components == ["New", "Deep", "Moved.pdf"])
        #expect(move?.from == ["Old", "Moved.pdf"])
        #expect(move?.parentId == plan.folders.last?.id)
        #expect(plan.movedFiles.count == 1 && plan.movedItems.isEmpty)
    }

    @Test("With hashes, the candidate with the item's hash is the moved file")
    func planPairsByHash() {
        var item = existing("Doc", file: "Old/Doc.pdf")
        item.contentHash = "same"
        let right = file("A/Doc.pdf"), wrong = file("B/Doc.pdf")
        let plan = CloudFolderScan.plan(
            files: [right, wrong], existing: [item], module: "pdf",
            hashes: [CloudFolderScan.key(right.components): "same", CloudFolderScan.key(wrong.components): "other"]
        )

        #expect(plan.moves.first?.file?.components == ["A", "Doc.pdf"])
        #expect(plan.items.map { $0.file.components } == [["B", "Doc.pdf"]], "the other file stays a new file")
        #expect(plan.removals.isEmpty)
    }

    @Test("A file with another hash than the item is not its moved file")
    func planRejectsDifferentHash() {
        var item = existing("Doc", file: "Old/Doc.pdf")
        item.contentHash = "mine"
        let candidate = file("New/Doc.pdf")
        let plan = CloudFolderScan.plan(files: [candidate], existing: [item], module: "pdf", hashes: [CloudFolderScan.key(candidate.components): "theirs"])

        #expect(plan.moves.isEmpty)
        #expect(plan.removals.map(\.id) == [item.id])
        #expect(plan.items.count == 1)
    }

    @Test("A file that is not downloaded matches by name, since it cannot be hashed")
    func planPairsPlaceholderByName() {
        var item = existing("Doc", file: "Old/Doc.pdf")
        item.contentHash = "mine"
        let plan = CloudFolderScan.plan(files: [CloudScanFile(components: ["New", "Doc.pdf"], isPlaceholder: true)], existing: [item], module: "pdf")

        #expect(plan.moves.count == 1)
        #expect(plan.removals.isEmpty)
    }

    @Test("Several candidates of one name without a deciding hash pair with nothing")
    func planDoesNotGuessBetweenCandidates() {
        let item = existing("Doc", file: "Old/Doc.pdf")
        let plan = CloudFolderScan.plan(files: [file("A/Doc.pdf"), file("B/Doc.pdf")], existing: [item], module: "pdf")

        #expect(plan.moves.isEmpty)
        #expect(plan.removals.map(\.id) == [item.id])
        #expect(plan.items.count == 2)
    }

    @Test("A file two items claim is the moved file of neither")
    func planDoesNotPairSharedCandidate() {
        let first = existing("Doc", file: "One/Doc.pdf")
        let second = existing("Doc", file: "Two/Doc.pdf")
        let plan = CloudFolderScan.plan(files: [file("New/Doc.pdf")], existing: [first, second], module: "pdf")

        #expect(plan.moves.isEmpty)
        #expect(Set(plan.removals.map(\.id)) == [first.id, second.id])
        #expect(plan.items.count == 1)
    }

    @Test("Hash candidates are the downloaded files that carry the name of an item with a hash whose file is gone")
    func hashCandidates() {
        var withHash = existing("Doc", file: "Old/Doc.pdf")
        withHash.contentHash = "h"
        let withoutHash = existing("Other", file: "Old/Other.pdf")
        let files = [file("New/Doc.pdf"), CloudScanFile(components: ["Cloud", "Doc.pdf"], isPlaceholder: true), file("New/Other.pdf"), file("New/Unrelated.pdf")]

        let candidates = CloudFolderScan.hashCandidates(files: files, existing: [withHash, withoutHash])

        #expect(candidates.map { $0.components.joined(separator: "/") } == ["New/Doc.pdf"])
    }

    // MARK: - Items in another folder than their file

    @Test("An item in another folder than its file moves into the file's folder")
    func planMovesItemToFileFolder() {
        let wrong = existing("Wrong", isFolder: true)
        let right = existing("Right", isFolder: true)
        let item = existing("Doc", parentId: wrong.id, file: "Right/Doc.pdf")
        let plan = CloudFolderScan.plan(files: [file("Right/Doc.pdf")], existing: [wrong, right, item], module: "pdf")

        #expect(plan.moves.count == 1)
        #expect(plan.moves.first?.file == nil, "the file stays where it is")
        #expect(plan.moves.first?.parentId == right.id)
        #expect(plan.moves.first?.from == ["Wrong"])
        #expect(plan.moves.first?.to == ["Right"])
        #expect(plan.folders.isEmpty && plan.items.isEmpty && plan.removals.isEmpty)
    }

    @Test("The folder of the file is created when the app has none, and a root file moves the item to the root")
    func planMovesItemToNewOrRootFolder() {
        let wrong = existing("Wrong", isFolder: true)
        let inNew = existing("A", parentId: wrong.id, file: "Fresh/A.pdf")
        let toRoot = existing("B", parentId: wrong.id, file: "B.pdf")
        let plan = CloudFolderScan.plan(files: [file("Fresh/A.pdf"), file("B.pdf")], existing: [wrong, inNew, toRoot], module: "pdf")

        #expect(plan.folders.map(\.name) == ["Fresh"])
        #expect(plan.moves.first { $0.id == inNew.id }?.parentId == plan.folders.first?.id)
        #expect(plan.moves.first { $0.id == toRoot.id }?.parentId == nil)
        #expect(plan.moves.first { $0.id == toRoot.id }?.to.isEmpty == true)
    }

    @Test("An item already in the folder of its file, by name, is left alone")
    func planLeavesMatchingItems() {
        let folder = existing("Folder", isFolder: true)
        let sameNamedFolder = existing("folder", isFolder: true)
        let atRoot = existing("Root", file: "Root.pdf")
        let inFolder = existing("In", parentId: folder.id, file: "Folder/In.pdf")
        let inTwin = existing("Twin", parentId: sameNamedFolder.id, file: "Folder/Twin.pdf")
        let plan = CloudFolderScan.plan(
            files: [file("Root.pdf"), file("Folder/In.pdf"), file("Folder/Twin.pdf")],
            existing: [folder, sameNamedFolder, atRoot, inFolder, inTwin],
            module: "pdf"
        )

        #expect(plan.isEmpty)
    }

    @Test("An item in a collection or a trashed folder is not moved to the folder of its file")
    func planIgnoresItemsOutsideFolders() {
        let collection = existing("Collection")
        let trashed = existing("Trashed", isFolder: true, isTrashed: true)
        let inCollection = existing("A", parentId: collection.id, file: "Folder/A.pdf")
        let inTrash = existing("B", parentId: trashed.id, file: "Folder/B.pdf")
        let plan = CloudFolderScan.plan(files: [file("Folder/A.pdf"), file("Folder/B.pdf")], existing: [collection, trashed, inCollection, inTrash], module: "pdf")

        #expect(plan.moves.isEmpty)
    }

    @Test("An item whose folder is not in the library moves into the folder of its file")
    func planMovesOrphanedItemToFileFolder() {
        // Items sent by a game master keep the id of the master's folder, which this library
        // does not have: the item is listed nowhere in folder mode and sync said "in sync".
        let missingFolderId = UUID()
        let orphan = existing("Kapitel 1", parentId: missingFolderId, file: "Audio Text Roman/Kapitel 1.mp3")
        let plan = CloudFolderScan.plan(files: [file("Audio Text Roman/Kapitel 1.mp3")], existing: [orphan], module: "audio")

        #expect(plan.folders.map(\.name) == ["Audio Text Roman"])
        #expect(plan.moves.count == 1)
        #expect(plan.moves.first?.id == orphan.id)
        #expect(plan.moves.first?.file == nil, "the file stays where it is, only the item moves")
        #expect(plan.moves.first?.parentId == plan.folders.first?.id)
    }

    @Test("An item whose folder is not in the library moves to the root when its file is there")
    func planMovesOrphanedItemWithRootFileToRoot() {
        let orphan = existing("Top", parentId: UUID(), file: "Top.mp3")
        let plan = CloudFolderScan.plan(files: [file("Top.mp3")], existing: [orphan], module: "audio")

        #expect(plan.folders.isEmpty)
        #expect(plan.moves.map(\.id) == [orphan.id])
        #expect(plan.moves.first?.parentId == nil)
    }

    @Test("An orphaned item reuses the folder of its file when the library has it")
    func planMovesOrphanedItemIntoExistingFolder() {
        let folder = existing("Audio Text Roman", isFolder: true)
        let orphan = existing("Kapitel 1", parentId: UUID(), file: "Audio Text Roman/Kapitel 1.mp3")
        let plan = CloudFolderScan.plan(files: [file("Audio Text Roman/Kapitel 1.mp3")], existing: [folder, orphan], module: "audio")

        #expect(plan.folders.isEmpty)
        #expect(plan.moves.first?.parentId == folder.id)
    }

    // MARK: - Selection

    @Test("Deselected entries are dropped, and with them the new folders only they needed")
    func restrictedDropsUnneededFolders() {
        let moving = existing("Moving", file: "Old/Moving.pdf")
        let plan = CloudFolderScan.plan(
            files: [file("Shared/Moving.pdf"), file("Shared/Added.pdf"), file("Only/Added Too.pdf")],
            existing: [moving, existing("Gone", file: "X/Gone.pdf")],
            module: "pdf"
        )
        #expect(plan.folders.map(\.name) == ["Shared", "Only"])
        let added = plan.items.first { $0.name == "Added" }!
        let addedToo = plan.items.first { $0.name == "Added Too" }!

        let withoutAddedToo = plan.restricted(toDeselected: [addedToo.id])
        #expect(withoutAddedToo.folders.map(\.name) == ["Shared"], "nothing selected needs 'Only'")

        let withoutAddedAndMove = plan.restricted(toDeselected: [added.id, moving.id, addedToo.id])
        #expect(withoutAddedAndMove.folders.isEmpty)

        let withoutAdded = plan.restricted(toDeselected: [added.id])
        #expect(withoutAdded.folders.map(\.name) == ["Shared", "Only"], "the move still needs 'Shared'")
        #expect(withoutAdded.items.map(\.name) == ["Added Too"])
    }

    @Test("A needed folder brings its new parents, and deselecting a removal keeps the item")
    func restrictedKeepsParentChain() throws {
        let gone = existing("Gone", file: "X/Gone.pdf")
        let plan = CloudFolderScan.plan(files: [file("A/B/C/New.pdf")], existing: [gone], module: "pdf")
        #expect(plan.removals.map(\.id) == [gone.id])

        let restricted = plan.restricted(toDeselected: [gone.id])

        #expect(restricted.removals.isEmpty)
        #expect(restricted.folders.map(\.name) == ["A", "B", "C"])
        #expect(Set(plan.selectableIds) == [plan.items[0].id, gone.id])
    }
}
