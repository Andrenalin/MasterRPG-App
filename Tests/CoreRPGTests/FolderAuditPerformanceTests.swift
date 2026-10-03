// @copyright André Trettin

import Foundation
import Testing
import UniformTypeIdentifiers

@testable import CoreRPG

/// CODE_AUDIT_Folder §7: hashing, file streaming, review memory and list lookups.
@Suite("Folder audit performance fixes")
@MainActor
struct FolderAuditPerformanceTests {
    // MARK: - §7.1 hashing and file streaming

    @Test("The off-actor hash equals the synchronous one (§7.1)")
    func offActorHashMatches() async {
        let data = Data((0..<3_000_000).map { UInt8(truncatingIfNeeded: $0) })

        #expect(await FileUrl.computeContentHash(of: data) == FileUrl.contentHash(of: data))
    }

    @Test("A stored file is hashed streamed from disk and read through a handle (§7.1)")
    func storedFileHashAndHandle() async throws {
        let module = "FolderAuditPerformance-\(UUID().uuidString)"
        let sut = FileUrlDataController(moduleFolder: module, fileTypes: [.data], filenameExtension: "bin")
        // More than one 1 MB block, with a partial last block.
        let data = Data((0..<2_500_000).map { UInt8(truncatingIfNeeded: $0 &* 31) })
        let url = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).bin")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let fileUrl = FileUrl(fileId: UUID(), url: url, location: .local, module: module, relativeUrl: nil)

        let hash = try await sut.contentHash(for: fileUrl)
        let handle = try #require(try await sut.readHandle(for: fileUrl))
        defer { try? handle.close() }
        let read = try handle.readToEnd()

        #expect(hash == FileUrl.contentHash(of: data))
        #expect(read == data)
    }

    @Test("Bytes held in memory are hashed without a file (§7.1)")
    func inMemoryBytesAreHashed() async throws {
        let module = "FolderAuditPerformance-\(UUID().uuidString)"
        let sut = FileUrlDataController(moduleFolder: module, fileTypes: [.data], filenameExtension: "bin")
        let data = Data("held".utf8)
        let fileUrl = FileUrl(importedData: data, fileId: UUID(), filename: "held.bin", module: module)

        #expect(try await sut.contentHash(for: fileUrl) == FileUrl.contentHash(of: data))
    }

    @Test("A supplied hash is kept instead of hashing the bytes again (§7.1)")
    func suppliedHashIsKept() {
        var fileUrl = FileUrl(importedData: Data("a".utf8), fileId: UUID(), filename: "a.bin", module: "m", contentHash: "given")
        #expect(fileUrl.contentHash == "given")

        fileUrl.resetData(Data("b".utf8), contentHash: "other")
        #expect(fileUrl.contentHash == "other")
        #expect(fileUrl.data == Data("b".utf8))
    }

    // MARK: - §7.3 review memory

    @Test("The review memory builds an item on first read and only once (§7.3)")
    func reviewMemoryIsLazyAndCached() {
        let readId = UUID()
        let built = BuiltIds()
        let memory = ReviewSheetMemory { itemId, _ in
            built.ids.append(itemId)
            return .item(FakeItemModel(id: itemId, name: "Built"))
        }

        let first = memory.item(for: readId, module: .adventure) as? FakeItemModel
        let second = memory.item(for: readId, module: .adventure) as? FakeItemModel

        #expect(built.ids == [readId], "only the read item is built, and once")
        #expect(first != nil && first === second)
    }

    @MainActor private final class BuiltIds {
        var ids: [UUID] = []
    }

    @Test("The decision signature changes with a decision (§7.3)")
    func signatureFollowsDecisions() {
        let itemId = UUID()
        let itemModel = SingleItemImportModel.from(item: SingleReviewItem(
            existing: FakeItemModel(id: itemId, name: "Existing"),
            imported: FakeItemModel(id: itemId, name: "Imported"),
            merged: FakeItemModel(id: itemId, name: "Merged")
        ))
        let reviewItem = ImportReviewItemModel(
            id: itemId,
            kind: .different,
            itemModel: itemModel
        )
        let reviewModel = ImportReviewModel(modules: [ImportReviewModule(id: .adventure, reviewItems: [reviewItem])])
        let before = reviewModel.sheetMemorySignature

        itemModel.applyItemDecision(.existing)

        #expect(reviewModel.sheetMemorySignature != before)
    }

    // MARK: - §7.4 list rows

    private func row(id: UUID = UUID(), itemId: UUID, level: Int = 0) -> FolderListItemModel {
        FolderListItemModel(
            id: id,
            source: ItemRowModel(itemId: itemId, typeId: .photo),
            level: level,
            isShown: false
        )
    }

    @Test("Rows are found by row id and by item id, first row first (§7.4)")
    func rowIndexLookups() {
        let itemId = UUID()
        let top = row(id: itemId, itemId: itemId)
        let nested = row(itemId: itemId, level: 1)
        let model = FolderListModel(navigationModel: ModuleNavigationModel())
        model.list = [top, nested]

        #expect(model.row(id: nested.id) === nested)
        #expect(model.row(itemId: itemId) === top)
        #expect(model.row(id: UUID()) == nil)
    }

    @Test("The row index follows every change of the list (§7.4)")
    func rowIndexIsRebuiltAfterChanges() {
        let first = row(itemId: UUID())
        let second = row(itemId: UUID())
        let model = FolderListModel(navigationModel: ModuleNavigationModel())
        model.list = [first]
        #expect(model.row(id: first.id) === first)

        model.list.append(second)
        #expect(model.row(id: second.id) === second)

        model.deleteItems(offsets: IndexSet(integer: 0))
        #expect(model.row(id: first.id) == nil)
        #expect(model.selectedItemId == nil)
    }

    @Test("A row equals itself without walking its children, and copies still compare them (§7.4)")
    func rowEquality() {
        let parent = row(itemId: UUID())
        parent.children = [row(itemId: UUID(), level: 1)]
        let copy = parent.deepCopy()

        #expect(parent == parent)
        #expect(parent == copy)
        copy.children = []
        #expect(parent != copy)
    }
}
