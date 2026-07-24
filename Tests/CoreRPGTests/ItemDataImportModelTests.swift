// @copyright André Trettin

import Testing
@testable import CoreRPG

@MainActor
@Suite("Item data import progress")
struct ItemDataImportModelTests {
    @Test("Finalization starts only after every item is processed")
    func finalizationBoundary() {
        let model = ItemDataImportModel()
        model.totalImportingItems = 8

        #expect(!model.isFinalizingImport)

        model.isImportRunning = true
        model.importedItems = 7
        #expect(!model.isFinalizingImport)

        model.importedItems = 8
        #expect(model.isFinalizingImport)

        model.importedItems = 9
        #expect(model.isFinalizingImport)

        model.isImportRunning = false
        #expect(!model.isFinalizingImport)
    }
}
