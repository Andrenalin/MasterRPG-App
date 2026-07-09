//// @copyright André Trettin
//
//import Foundation
//import Testing
//
//@testable import CoreRPG
//
//@MainActor
//struct ReviewSheetMemoryTests {
//    @Test func reviewAwareLookupPrefersReviewMemory() throws {
//        let itemId = UUID()
//        let liveItem = FakeItemModel(id: itemId, name: "Live Item")
//        let reviewItem = FakeItemModel(id: itemId, name: "Review Item")
//        let controller = fakeController(with: liveItem)
//        let rootManager = RootManager(
//            anyRoot: ItemRootController.fake,
//            reviewSheetMemory: ReviewSheetMemory(items: [.adventure: [itemId: reviewItem]])
//        )
//
//        let result = controller.reviewAwareItemOrEmpty(root: rootManager, for: itemId)
//
//        #expect(result.name == "Review Item")
//    }
//
//    @Test func reviewAwareLookupCanHideLiveItem() throws {
//        let itemId = UUID()
//        let liveItem = FakeItemModel(id: itemId, name: "Live Item")
//        let controller = fakeController(with: liveItem)
//        let rootManager = RootManager(
//            anyRoot: ItemRootController.fake,
//            reviewSheetMemory: ReviewSheetMemory(items: [:], hiddenItemIds: [.adventure: [itemId]])
//        )
//
//        let hidden = controller.reviewAwareItemSync(root: rootManager, for: itemId)
//        let empty = controller.reviewAwareItemOrEmpty(root: rootManager, for: itemId)
//
//        #expect(hidden == nil)
//        #expect(empty.id == itemId)
//        #expect(empty.name.isEmpty)
//    }
//
//    @Test func importReviewMemoryUsesCurrentDecision() throws {
//        let itemId = UUID()
//        let existing = FakeItemModel(id: itemId, name: "Existing Item", description: "Existing Description")
//        let imported = FakeItemModel(id: itemId, name: "Imported Item", description: "Imported Description")
//        let merged = FakeItemModel(id: itemId, name: "Merged Item", description: "Merged Description")
//        let itemModel = SingleItemImportModel.from(item: SingleReviewItem(existing: existing, imported: imported, merged: merged))
//        let reviewModel = ImportReviewModel(modules: [
//            ImportReviewModule(id: .adventure, reviewItems: [
//                ImportReviewItemModel(
//                    id: itemId,
//                    kind: .different,
//                    existingStatus: existing.name,
//                    importedStatus: imported.name,
//                    mergedStatus: merged.name,
//                    itemModel: itemModel
//                )
//            ])
//        ])
//
//        itemModel.applyItemDecision(.imported)
//        let importedMemory = reviewModel.sheetMemory()
//        let importedResult = try #require(importedMemory.item(for: itemId, module: .adventure) as? FakeItemModel)
//
//        itemModel.applyItemDecision(.existing)
//        let existingMemory = reviewModel.sheetMemory()
//        let existingResult = try #require(existingMemory.item(for: itemId, module: .adventure) as? FakeItemModel)
//
//        #expect(importedResult.name == "Imported Item")
//        #expect(importedResult.description == "Imported Description")
//        #expect(existingResult.name == "Existing Item")
//        #expect(existingResult.description == "Existing Description")
//    }
//
//    @Test func importReviewMemoryHidesDeletionWhenImportDecisionIsSelected() throws {
//        let itemId = UUID()
//        let deleted = FakeItemModel(id: itemId, name: "Deleted Item")
//        let itemModel = SingleItemImportModel.from(item: SingleReviewItem(existing: deleted, imported: deleted, merged: deleted))
//        let reviewModel = ImportReviewModel(modules: [
//            ImportReviewModule(id: .adventure, reviewItems: [
//                ImportReviewItemModel(
//                    id: itemId,
//                    kind: .different,
//                    existingStatus: deleted.name,
//                    importedStatus: "Not in import",
//                    mergedStatus: deleted.name,
//                    itemModel: itemModel,
//                    isDeletion: true
//                )
//            ])
//        ])
//
//        itemModel.applyItemDecision(.imported)
//        let memory = reviewModel.sheetMemory()
//
//        #expect(memory.hides(itemId: itemId, module: .adventure))
//        #expect(memory.item(for: itemId, module: .adventure) == nil)
//    }
//
//    private func fakeController(with item: FakeItemModel) -> FakeItemController {
//        let itemDataModel = ItemDataModel(categoryTags: [.all])
//        itemDataModel.items = [item.id]
//        itemDataModel.itemData[item.id] = item
//
//        return FakeItemController(
//            config: FakeModuleConfiguration(),
//            linkRegisterController: LinkRegisterController.fake,
//            itemDataModel: itemDataModel
//        )
//    }
//}
