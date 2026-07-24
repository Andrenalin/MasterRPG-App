// @copyright André Trettin

import Foundation
import Testing

@testable import CoreRPG
@testable import PhotoRPG

@MainActor
struct ExternalImportTests {
    @Test func stagingAndReviewDoNotLoadAttachmentOrMutateFakeLibrary() async throws {
        let root = ItemRootController.previewFixture()
        let itemID = UUID()
        let model = FakeItemModel(id: itemID, name: "Staged")
        let loadCount = LoadCount()
        let attachment = ExternalImportAttachment(
            suggestedFilename: "portrait.png",
            load: {
                await loadCount.increase()
                return Data([1, 2, 3])
            }
        )
        let provenance = ExternalImportProvenance(source: "Test")
        let item = ExternalImportBatchItem(
            id: itemID,
            module: .adventure,
            name: "Staged",
            model: model,
            provenance: provenance,
            attachment: attachment
        )

        let batch = ExternalImportBatch(
            title: "Partial",
            provenance: provenance,
            items: [item]
        )
        let session = ExternalImportReviewSession(batch: batch)

        #expect(batch.isPartial)
        #expect(session.phase == .reviewing)
        #expect(session.decision(for: item) == .merge)
        #expect(root.itemControllable.itemSync(for: itemID) == nil)
        let attachmentLoads = await loadCount.value
        #expect(attachmentLoads == 0)
    }

    @Test func itemDecisionsRemainIndependentAndStable() {
        let provenance = ExternalImportProvenance(source: "Test")
        let firstID = UUID()
        let secondID = UUID()
        let first = ExternalImportBatchItem(
            id: firstID,
            module: .adventure,
            name: "First",
            model: FakeItemModel(id: firstID, name: "First"),
            provenance: provenance
        )
        let second = ExternalImportBatchItem(
            id: secondID,
            module: .adventure,
            name: "Second",
            model: FakeItemModel(id: secondID, name: "Second"),
            provenance: provenance
        )
        let session = ExternalImportReviewSession(
            batch: ExternalImportBatch(
                title: "Stable decisions",
                provenance: provenance,
                items: [second, first]
            )
        )

        session.setDecision(.replace, for: first)
        session.setDecision(.skip, itemID: secondID, module: .adventure)

        #expect(session.decision(for: first) == .replace)
        #expect(session.decision(for: second) == .skip)
    }

    @Test func skippingEverythingDoesNotLoadSaveOrMutate() async throws {
        let root = ItemRootController.previewFixture()
        let itemID = UUID()
        let loadCount = LoadCount()
        let saveCount = LoadCount()
        let provenance = ExternalImportProvenance(source: "Test")
        let item = ExternalImportBatchItem(
            id: itemID,
            module: .adventure,
            name: "Skipped",
            model: FakeItemModel(id: itemID, name: "Skipped"),
            provenance: provenance,
            attachment: ExternalImportAttachment(
                suggestedFilename: "skipped.dat",
                load: {
                    await loadCount.increase()
                    return Data([0])
                }
            )
        )
        let session = ExternalImportReviewSession(
            batch: ExternalImportBatch(
                title: "Skipped",
                provenance: provenance,
                items: [item]
            ),
            defaultDecision: .skip
        )

        let result = try await session.commit(
            rootManager: RootManager(anyRoot: root),
            consolidatedSave: { await saveCount.increase() }
        )

        #expect(result.skippedItemCount == 1)
        #expect(session.phase == .completed)
        #expect(root.itemControllable.itemSync(for: itemID) == nil)
        let attachmentLoads = await loadCount.value
        let saves = await saveCount.value
        #expect(attachmentLoads == 0)
        #expect(saves == 0)
    }

    @Test func failedRollbackIsReportedInsteadOfClaimingSuccess() async {
        let root = ItemRootController.previewFixture()
        let itemID = UUID()
        let saveCount = LoadCount()
        let provenance = ExternalImportProvenance(source: "Test")
        let item = ExternalImportBatchItem(
            id: itemID,
            module: .adventure,
            name: "Rollback",
            model: FakeItemModel(id: itemID, name: "Rollback", category: .entry),
            provenance: provenance
        )
        let session = ExternalImportReviewSession(
            batch: ExternalImportBatch(
                title: "Rollback",
                provenance: provenance,
                items: [item]
            )
        )

        do {
            _ = try await session.commit(
                rootManager: RootManager(anyRoot: root),
                consolidatedSave: {
                    await saveCount.increase()
                    throw SaveFailure()
                }
            )
            Issue.record("Expected the consolidated save to fail")
        } catch {
            guard let importError = error as? ExternalImportError,
                  case .rollbackIncomplete = importError else {
                Issue.record("Expected an incomplete rollback error, got \(error)")
                return
            }
        }

        let saves = await saveCount.value
        #expect(saves == 2)
        #expect(session.phase == .failed)
        #expect(root.itemControllable.itemSync(for: itemID) == nil)
    }

    @Test func thrownSaveRollsBackAndSurfacesOriginalErrorWhenRestoreSaves() async {
        let root = ItemRootController.previewFixture()
        let itemID = UUID()
        let saveCount = LoadCount()
        let provenance = ExternalImportProvenance(source: "Test")
        let item = ExternalImportBatchItem(
            id: itemID,
            module: .adventure,
            name: "Rollback",
            model: FakeItemModel(id: itemID, name: "Rollback", category: .entry),
            provenance: provenance
        )
        let session = ExternalImportReviewSession(
            batch: ExternalImportBatch(title: "Rollback", provenance: provenance, items: [item])
        )

        do {
            _ = try await session.commit(
                rootManager: RootManager(anyRoot: root),
                consolidatedSave: {
                    await saveCount.increase()
                    if await saveCount.value == 1 { throw SaveFailure() }
                }
            )
            Issue.record("Expected the first consolidated save to fail")
        } catch {
            #expect(error is SaveFailure)
        }

        let saves = await saveCount.value
        #expect(saves == 2)
        #expect(session.phase == .failed)
        #expect(root.itemControllable.itemSync(for: itemID) == nil)
    }

    @Test func persistenceStagingFailureAbortsBeforeInMemoryInsert() async {
        let root = ItemRootController.previewFixture(
            dataControllable: PersistenceFailureStub(failReplace: true)
        )
        let itemID = UUID()
        let provenance = ExternalImportProvenance(source: "Test")
        let item = ExternalImportBatchItem(
            id: itemID,
            module: .adventure,
            name: "Cannot stage",
            model: FakeItemModel(id: itemID, name: "Cannot stage", category: .entry),
            provenance: provenance
        )
        let session = ExternalImportReviewSession(
            batch: ExternalImportBatch(title: "Staging", provenance: provenance, items: [item])
        )

        do {
            _ = try await session.commit(
                rootManager: RootManager(anyRoot: root),
                consolidatedSave: {}
            )
            Issue.record("Expected persistence staging to fail")
        } catch {
            #expect(error is PersistenceStagingFailure)
        }

        #expect(session.phase == .failed)
        #expect(root.itemControllable.itemSync(for: itemID) == nil)
    }

    @Test func rollbackDeleteStagingFailureIsReported() async {
        let root = ItemRootController.previewFixture(
            dataControllable: PersistenceFailureStub(failDelete: true)
        )
        let itemID = UUID()
        let saveCount = LoadCount()
        let provenance = ExternalImportProvenance(source: "Test")
        let item = ExternalImportBatchItem(
            id: itemID,
            module: .adventure,
            name: "Cannot roll back",
            model: FakeItemModel(id: itemID, name: "Cannot roll back", category: .entry),
            provenance: provenance
        )
        let session = ExternalImportReviewSession(
            batch: ExternalImportBatch(title: "Rollback staging", provenance: provenance, items: [item])
        )

        do {
            _ = try await session.commit(
                rootManager: RootManager(anyRoot: root),
                consolidatedSave: {
                    await saveCount.increase()
                    if await saveCount.value == 1 {
                        throw SaveFailure()
                    }
                }
            )
            Issue.record("Expected rollback to be incomplete")
        } catch {
            guard let importError = error as? ExternalImportError,
                  case .rollbackIncomplete(_, let rollbackErrors) = importError else {
                Issue.record("Expected rollbackIncomplete, got \(error)")
                return
            }
            #expect(rollbackErrors.contains { $0.contains("Could not restore") })
        }

        #expect(root.itemControllable.itemSync(for: itemID) != nil)
        #expect(session.phase == .failed)
    }

    @Test func failedSaveRestoresRepairLinkRegisterSideEffects() async {
        let root = ItemRootController.previewFixture()
        let itemID = UUID()
        let destinationID = UUID()
        let provenance = ExternalImportProvenance(source: "Test")
        let existingLink = LinkRegisterModel(
            name: "Pre-import link",
            source: ItemRowModel(itemId: itemID, typeId: .adventure),
            destination: ItemRowModel(itemId: destinationID, typeId: .photo)
        )
        root.editControllable.linkRegisterController.register(links: [existingLink])

        let item = ExternalImportBatchItem(
            id: itemID,
            module: .adventure,
            name: "Repair links",
            model: FakeItemModel(id: itemID, name: "Repair links", category: .entry),
            provenance: provenance
        )
        let session = ExternalImportReviewSession(
            batch: ExternalImportBatch(title: "Repair rollback", provenance: provenance, items: [item])
        )
        let saveCount = LoadCount()

        do {
            _ = try await session.commit(
                rootManager: RootManager(anyRoot: root),
                consolidatedSave: {
                    await saveCount.increase()
                    if await saveCount.value == 1 {
                        throw SaveFailure()
                    }
                }
            )
            Issue.record("Expected save failure")
        } catch {
            #expect(error is SaveFailure)
        }

        let restoredLinks = root.editControllable.linkRegisterController.model.items[destinationID]
        #expect(restoredLinks == [existingLink])
        #expect(root.itemControllable.itemSync(for: itemID) == nil)
    }

    @Test func failedSaveRestoresUnselectedPhotoChangedByRepair() async {
        let photoRoot = PhotoRootModel.testRoot()
        let childID = UUID()
        let importedID = UUID()
        let child = PhotoModel(
            id: childID,
            name: "Unselected child",
            category: .entry,
            displayState: 1
        )
        photoRoot.itemController.replace(model: child, isInsert: true, forceSave: true)

        let imported = PhotoModel(
            id: importedID,
            name: "Imported group",
            category: .entry,
            entries: [.newChild(id: childID)]
        )
        let provenance = ExternalImportProvenance(source: "Test")
        let item = ExternalImportBatchItem(
            id: importedID,
            module: .photo,
            name: imported.name,
            model: imported,
            provenance: provenance
        )
        let session = ExternalImportReviewSession(
            batch: ExternalImportBatch(title: "Repair model rollback", provenance: provenance, items: [item])
        )
        let saveCount = LoadCount()
        let sawRepairMutation = RepairObservation()

        do {
            _ = try await session.commit(
                rootManager: RootManager(anyRoot: photoRoot),
                consolidatedSave: {
                    await saveCount.increase()
                    if await saveCount.value == 1 {
                        let repairedDisplayState = await MainActor.run {
                            photoRoot.itemController.itemSync(for: childID)?.displayState
                        }
                        await sawRepairMutation.record(repairedDisplayState == 0)
                        throw SaveFailure()
                    }
                }
            )
            Issue.record("Expected save failure")
        } catch {
            #expect(error is SaveFailure)
        }

        #expect(await sawRepairMutation.value)
        #expect(photoRoot.itemController.itemSync(for: childID)?.displayState == 1)
        #expect(photoRoot.itemController.itemSync(for: importedID) == nil)
    }

    @Test func importedFileFactoryKeepsBytesTransientAndHashesThem() {
        let data = Data([4, 5, 6])
        let fileID = UUID()

        let file = FileUrl(
            importedData: data,
            fileId: fileID,
            filename: "image.webp",
            module: NetworkModules.photo.token
        )

        #expect(file.fileId == fileID)
        #expect(file.location == .newCloud)
        #expect(file.data == data)
        #expect(file.contentHash == FileUrl.contentHash(of: data))
        #expect(file.rawUrl.lastPathComponent == "image.webp")
        #expect(!file.rawUrl.isFileURL)
    }
}

private actor LoadCount {
    private(set) var value = 0

    func increase() {
        value += 1
    }
}

private actor RepairObservation {
    private(set) var value = false

    func record(_ value: Bool) {
        self.value = value
    }
}

private struct SaveFailure: Error {}

private struct PersistenceStagingFailure: Error {}

private struct PersistenceFailureStub: DataPersistenceControllable {
    init(failReplace: Bool = false, failDelete: Bool = false) {
        self.failReplace = failReplace
        self.failDelete = failDelete
    }

    let failReplace: Bool
    let failDelete: Bool

    func fetch(id: UUID) async throws -> ModelType? { nil }
    func fetchAll() async throws -> [any ModelType] { [] }
    func fetchIds() async throws -> [UUID] { [] }

    func delete(id: UUID) async throws {
        if failDelete { throw PersistenceStagingFailure() }
    }

    func batchDelete(ids: [UUID]) async throws {}

    @MainActor
    func replaceSync(id: UUID, with viewModel: any ModelType) throws {
        if failReplace { throw PersistenceStagingFailure() }
    }

    func replace(id: UUID, with viewModel: any ModelType) async throws {
        if failReplace { throw PersistenceStagingFailure() }
    }

    func save() async throws {}
    func flushPendingOperations() async throws {}
}
