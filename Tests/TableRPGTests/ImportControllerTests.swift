// @copyright André Trettin

@testable import CoreRPG
import Foundation
import DiceRPG
import PdfRPG
import RPGResourcesDebug
import Testing

@testable import TableRPG

@MainActor
struct ImportControllerTests {
    @Test func importing() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)


        let sut = root.importController

        let bundle = ResourcesDebug.bundle
        let url = bundle.url(forResource: ResourcesDebug.tableTestData, withExtension: "gmz").unsafelyUnwrapped

        let task = sut.importUrl(from: url)
        let _ = try await task.value
        #expect(root.itemController.itemDataModel.items.count == 16)
    }

    @Test func importingNestedTableLinksRegistersAllLinks() async throws {
        // Given
        let sourceRoot = TableRootModel.testRoot(diceRoot: DiceRootModel.testRoot(), pdfRoot: PdfRootModel.testRoot())

        let linkedTables = createNestedLinkedTables(in: sourceRoot)
        assertRegisteredNestedLinks(in: sourceRoot, linkedTables: linkedTables)

        let exportIds = sourceRoot.exportController.exporting(itemIds: ItemModuleIds(ids: Set([linkedTables.tableAId]), module: .table))
        let exportedTableIds = try #require(exportIds.ids[.table])
        #expect(Set(exportedTableIds) == [linkedTables.tableAId, linkedTables.tableBId, linkedTables.tableCId])

        let stream = OutputStream.toMemory()
        stream.open()
        defer { stream.close() }
        _ = try await sourceRoot.exportController.export(itemIds: exportIds, into: stream)
        let data = try #require(stream.property(forKey: Stream.PropertyKey.dataWrittenToMemoryStreamKey) as? Data)

        let importedRoot = TableRootModel.testRoot(diceRoot: DiceRootModel.testRoot(), pdfRoot: PdfRootModel.testRoot())
        let importStream = InputStream(data: data)
        importStream.open()
        defer { importStream.close() }

        // When
        try await importedRoot.importController.importStream(from: importStream, forceSave: false)

        // Then
        #expect(Set(importedRoot.itemController.itemDataModel.items) == [linkedTables.tableAId, linkedTables.tableBId, linkedTables.tableCId])
        assertRegisteredNestedLinks(in: importedRoot, linkedTables: linkedTables)
    }

    @Test("A cancelled import throws instead of finishing silently (CODE_AUDIT_Folder §3.3)")
    func cancelledImportThrows() async throws {
        let sourceRoot = TableRootModel.testRoot(diceRoot: DiceRootModel.testRoot(), pdfRoot: PdfRootModel.testRoot())
        let tableId = sourceRoot.itemController.addNewSync(type: .item)
        sourceRoot.editController.save(updated: TableModel(id: tableId, name: "Loot", entries: []), message: "Create table", forceSave: false)
        let exportIds = sourceRoot.exportController.exporting(itemIds: ItemModuleIds(ids: Set([tableId]), module: .table))
        let stream = OutputStream.toMemory()
        stream.open()
        _ = try await sourceRoot.exportController.export(itemIds: exportIds, into: stream)
        stream.close()
        let data = try #require(stream.property(forKey: Stream.PropertyKey.dataWrittenToMemoryStreamKey) as? Data)

        let importedRoot = TableRootModel.testRoot(diceRoot: DiceRootModel.testRoot(), pdfRoot: PdfRootModel.testRoot())
        let importTask = Task { @MainActor in
            let importStream = InputStream(data: data)
            importStream.open()
            defer { importStream.close() }
            try await importedRoot.importController.importStream(from: importStream, forceSave: false)
        }
        importTask.cancel()

        await #expect(throws: CancellationError.self) {
            try await importTask.value
        }
        #expect(importedRoot.itemController.itemDataModel.items.isEmpty)
    }

    private func createNestedLinkedTables(in root: TableRootModel) -> NestedLinkedTables {
        let tableCId = root.itemController.addNewSync(type: .item)
        let entryCId = UUID()
        let tableC = TableModel(
            id: tableCId,
            name: "Table C",
            entries: [
                TableEntryModel(id: entryCId, name: "Entry C", content: "Treasure")
            ]
        )
        root.editController.save(updated: tableC, message: "Create Table C", forceSave: false)

        let tableCEntryLink = root.linkController.generateLink(linkNumber: 0, itemId: tableCId, entryId: entryCId)
        let tableBId = root.itemController.addNewSync(type: .item)
        let entryBId = UUID()
        let tableB = TableModel(
            id: tableBId,
            name: "Table B",
            entries: [
                TableEntryModel(id: entryBId, name: "Entry B", content: tableCEntryLink)
            ]
        )
        root.editController.save(updated: tableB, message: "Create Table B", forceSave: false)

        let tableBLink = root.linkController.generateLink(linkNumber: 0, itemId: tableBId, entryId: nil)
        let tableAId = root.itemController.addNewSync(type: .item)
        let entryAId = UUID()
        let tableA = TableModel(
            id: tableAId,
            name: "Table A",
            entries: [
                TableEntryModel(id: entryAId, name: "Entry A", content: tableBLink)
            ]
        )
        root.editController.save(updated: tableA, message: "Create Table A", forceSave: false)

        return NestedLinkedTables(
            tableAId: tableAId,
            entryAId: entryAId,
            tableBId: tableBId,
            entryBId: entryBId,
            tableCId: tableCId,
            entryCId: entryCId
        )
    }

    private func assertRegisteredNestedLinks(in root: TableRootModel, linkedTables: NestedLinkedTables) {
        let sourceA = ItemRowModel(itemId: linkedTables.tableAId, entryId: linkedTables.entryAId, typeId: .table)
        let sourceB = ItemRowModel(itemId: linkedTables.tableBId, entryId: linkedTables.entryBId, typeId: .table)
        let destinationB = ItemRowModel(itemId: linkedTables.tableBId, typeId: .table)
        let destinationCEntry = ItemRowModel(itemId: linkedTables.tableCId, entryId: linkedTables.entryCId, typeId: .table)

        let register = root.itemController.linkRegisterController.model.items
        let tableBLinks = register[linkedTables.tableBId] ?? []
        let tableCLinks = register[linkedTables.tableCId] ?? []

        #expect(tableBLinks.map(\.source) == [sourceA])
        #expect(tableBLinks.map(\.destination) == [destinationB])
        #expect(tableCLinks.map(\.source) == [sourceB])
        #expect(tableCLinks.map(\.destination) == [destinationCEntry])
        #expect(register.values.reduce(0) { $0 + $1.count } == 2)
    }
}

private struct NestedLinkedTables {
    let tableAId: UUID
    let entryAId: UUID
    let tableBId: UUID
    let entryBId: UUID
    let tableCId: UUID
    let entryCId: UUID
}

private extension ItemController {
    @MainActor func addNewSync(type: ItemListCategory) -> UUID {
        let model = TableModel.empty.copy()
        model.category = type
        resetModel(with: model)
        return model.id
    }
}
