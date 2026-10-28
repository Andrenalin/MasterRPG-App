// @copyright André Trettin

import CoreRPG
import Foundation
import RPGResourcesDebug
import Testing

@testable import SpaceRPG

/// Tests for `SearchListController` and `SearchLinkController` driving SpaceRPG search.
/// SpaceRPG uses the CoreRPG default `SearchControllable` implementations with no overrides,
/// so these tests pin the generic list/folder/inspector behaviour for non-Character modules.
@MainActor
struct FolderListControllerTests {

    // MARK: - Helpers

    private func makeRoot() async -> SpaceRootModel {
        let root = SpaceRootModel.testRoot()
        await root.itemController.resetData()
        return root
    }

    /// `SearchListController` + shared `ListDisplayModel`.
    private func makeSUT(for root: SpaceRootModel,
                         listMode: ListDisplayModel.ListMode = .list,
                         displayMode: ListDisplayModel.DisplayMode = .medium)
        -> (sut: SearchListController, ldm: ListDisplayModel)
    {
        let ldm = ListDisplayModel(displayMode: displayMode, listMode: listMode)
        let sut = SearchListController(
            searchController: root.searchControllable,
            searchModel: SearchModel.preview(module: .space),
            listDisplayModel: ldm
        )
        return (sut, ldm)
    }

    /// `SearchLinkController` + shared `ListDisplayModel` + its `SearchModel`.
    private func makeLinkSUT(for root: SpaceRootModel,
                              listMode: ListDisplayModel.ListMode = .list,
                              focusId: UUID? = nil)
        -> (sut: SearchLinkController, ldm: ListDisplayModel, sm: SearchModel)
    {
        let ldm = ListDisplayModel(displayMode: .medium, listMode: listMode)
        let sm  = SearchModel.preview(module: .space)
        sm.filterId = focusId
        let sut = SearchLinkController(
            searchController: root.searchControllable,
            searchModel: sm,
            listDisplayModel: ldm
        )
        return (sut, ldm, sm)
    }

    // MARK: - SearchListController: empty search loads list

    @Test("Empty list search returns all visible items sorted alphabetically")
    func emptySearchLoadsItemsAlphabetically() async throws {
        let root = await makeRoot()

        let idC = await root.itemController.addNew(type: .item)
        let idA = await root.itemController.addNew(type: .item)
        let idB = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Cruiser",  itemId: idC)
        root.editController.reset(name: "Asteroid", itemId: idA)
        root.editController.reset(name: "Battleship", itemId: idB)

        let (sut, _) = makeSUT(for: root)
        let results = await sut.results(text: "")

        let ids = results.map(\.itemId)
        #expect(ids.contains(idA) && ids.contains(idB) && ids.contains(idC),
                "All visible items must appear on empty search")
        let names = results.map(\.itemName)
        #expect(names == names.sorted { $0.localizedCompare($1) == .orderedAscending },
                "Empty-search results must be alphabetically sorted")
    }

    @Test("Empty list search excludes folders and collections")
    func emptySearchExcludesSpecialCategories() async throws {
        let root = await makeRoot()

        let itemId   = await root.itemController.addNew(type: .item)
        let folderId = await root.itemController.addNew(type: .folder)
        root.editController.reset(name: "Probe",  itemId: itemId)
        root.editController.reset(name: "Hangar", itemId: folderId)

        let (sut, _) = makeSUT(for: root)
        let results = await sut.results(text: "")

        let ids = results.map(\.itemId)
        #expect(ids.contains(itemId), "Regular item must appear in list mode")
        #expect(!ids.contains(folderId), "Folder must be excluded in list mode")
    }

    // MARK: - SearchListController: search text filters

    @Test("Non-empty list search filters to matching items by relevance")
    func searchTextFiltersAndSortsByRelevance() async throws {
        let root = await makeRoot()

        let exactId    = await root.itemController.addNew(type: .item)
        let containsId = await root.itemController.addNew(type: .item)
        let noMatchId  = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Dragon",           itemId: exactId)
        root.editController.reset(name: "The Dragon Ship",  itemId: containsId)
        root.editController.reset(name: "Nebula Cruiser",   itemId: noMatchId)

        let (sut, _) = makeSUT(for: root)
        let results = await sut.results(text: "Dragon")
        let ids = results.map(\.itemId)

        #expect(ids.contains(exactId),    "Exact match must appear")
        #expect(ids.contains(containsId), "Contains match must appear")
        #expect(!ids.contains(noMatchId), "Non-matching item must be excluded")

        let exactIdx    = try #require(ids.firstIndex(of: exactId))
        let containsIdx = try #require(ids.firstIndex(of: containsId))
        #expect(exactIdx < containsIdx, "Exact name match must rank above contains match")
    }

    @Test("Compact mode matches name only; description match requires medium or above")
    func displayModeControlsDescriptionMatching() async throws {
        let root = await makeRoot()

        let descOnlyId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Wanderer",              itemId: descOnlyId)
        root.editController.reset(description: "Dragon-class scout vessel", itemId: descOnlyId)

        // Compact: name only — description match must NOT appear
        let (compactSUT, _) = makeSUT(for: root, displayMode: .compact)
        let compactResults = await compactSUT.results(text: "Dragon")
        #expect(!compactResults.map(\.itemId).contains(descOnlyId),
                "Compact mode must not match by description")

        // Medium: name + description — must appear
        let (mediumSUT, _) = makeSUT(for: root, displayMode: .medium)
        let mediumResults = await mediumSUT.results(text: "Dragon")
        #expect(mediumResults.map(\.itemId).contains(descOnlyId),
                "Medium mode must match by description")
    }

    // MARK: - SearchListController: folder mode

    @Test("Switching to folder mode returns folder as parent with matching item as child")
    func switchingToFolderModeReturnsHierarchicalResults() async throws {
        let root = await makeRoot()

        let folderId = await root.itemController.addNew(type: .folder)
        let itemId   = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Dragon Dock", itemId: folderId)
        root.editController.reset(name: "Dragon Wing", itemId: itemId)
        root.editController.addItem(itemId: itemId, parentId: folderId)

        let (sut, ldm) = makeSUT(for: root, listMode: .list)

        // List mode: folder and item both appear flat, folder result has no children
        let listResults = await sut.results(text: "Dragon")
        if let folderFlat = listResults.first(where: { $0.itemId == folderId }) {
            #expect(folderFlat.children.isEmpty, "List mode folder must carry no children")
        }

        // Switch to folder mode on the same SearchListController
        ldm.listMode = .folder
        let folderResults = await sut.results(text: "Dragon")

        let folderResult = try #require(
            folderResults.first(where: { $0.itemId == folderId }),
            "Folder must appear in folder mode")
        #expect(folderResult.children.map(\.itemId).contains(itemId),
                "Item must be nested inside the folder in folder mode")
    }

    @Test("Folder mode empty search: items grouped under parent; children lazy (empty children list)")
    func folderModeEmptySearchLazyLoadsChildren() async throws {
        let root = await makeRoot()

        let folderId  = await root.itemController.addNew(type: .folder)
        let memberA   = await root.itemController.addNew(type: .item)
        let standalone = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Fleet HQ",    itemId: folderId)
        root.editController.reset(name: "Fighter",     itemId: memberA)
        root.editController.reset(name: "Lone Probe",  itemId: standalone)
        root.editController.addItem(itemId: memberA, parentId: folderId)

        let (sut, _) = makeSUT(for: root, listMode: .folder)
        let results = await sut.results(text: "")

        let rootIds = results.map(\.itemId)
        #expect(rootIds.contains(folderId),   "Folder must be a root node")
        #expect(rootIds.contains(standalone), "Standalone item must be a root node")
        #expect(!rootIds.contains(memberA),   "Folder member must not appear at root level")

        // Empty search uses lazy loading — SearchResult.children is empty;
        // FolderListControllable populates item.children on open via loadFolderChildren.
        let folderResult = try #require(results.first(where: { $0.itemId == folderId }))
        #expect(folderResult.children.isEmpty,
                "Lazy loading: folder SearchResult.children is empty on empty search")
    }

    // MARK: - SearchLinkController: inspector search

    @Test("Inspector empty search without focus returns all visible items sorted alphabetically")
    func inspectorEmptyNoFocusReturnsAllItems() async throws {
        let root = await makeRoot()
        let itemId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Probe", itemId: itemId)

        let (sut, _, _) = makeLinkSUT(for: root)
        let results = await sut.results(text: "")
        #expect(results.map(\.itemId).contains(itemId),
                "Empty search must return all visible items — fixes first-appear blank list")
    }

    @Test("Inspector search returns matching items")
    func inspectorSearchReturnsMatchingItems() async throws {
        let root = await makeRoot()

        let matchId   = await root.itemController.addNew(type: .item)
        let noMatchId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Dragon Ship",  itemId: matchId)
        root.editController.reset(name: "Space Station", itemId: noMatchId)

        let (sut, _, _) = makeLinkSUT(for: root)
        let results = await sut.results(text: "Dragon")

        let ids = results.map(\.itemId)
        #expect(ids.contains(matchId),    "Dragon Ship must appear")
        #expect(!ids.contains(noMatchId), "Space Station must be excluded")
    }

    @Test("Inspector search: item with matching description appears in medium mode")
    func inspectorSearchMatchesDescriptionInMediumMode() async throws {
        let root = await makeRoot()

        let itemId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Wanderer", itemId: itemId)
        root.editController.reset(description: "Dragon-class scout", itemId: itemId)

        let (sut, _, _) = makeLinkSUT(for: root)    // medium by default
        let results = await sut.results(text: "Dragon")
        #expect(results.map(\.itemId).contains(itemId),
                "Inspector must match by description in medium mode")
    }

    @Test("Inspector search: entry name match produces entry as child of item result")
    func inspectorEntryNameMatchIsChild() async throws {
        let root = await makeRoot()

        // SpaceEntryModel.name always returns "Space Model".
        // Searching "Space" triggers an entry match, so the entry must appear as
        // a child of the item result (not a flat sibling).
        let itemId   = await root.itemController.addNew(type: .item)
        let linkedId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Galaxy Base", itemId: itemId)
        // Append an entry that links to another 3D object; its name = "Space Model"
        let entryId = UUID()
        root.itemController.itemOrEmpty(for: itemId)
            .entries.append(SpaceEntryModel(id: entryId, spaceId: linkedId))

        let (sut, _, _) = makeLinkSUT(for: root)
        // "Space" matches entry.name "Space Model" → entry becomes a child of the item result
        let results = await sut.results(text: "Space")

        let itemResult = try #require(results.first(where: { $0.itemId == itemId }),
                                      "Galaxy Base must appear because its entry name matches")
        #expect(itemResult.children.contains(where: { $0.entryId == entryId }),
                "Matching entry must be a child of the item result, not a flat sibling")
        #expect(results.allSatisfy { $0.entryId == nil },
                "No entry-level result must appear at the top level")
    }

    @Test("Inspector with focusId searches only the focused item")
    func inspectorFocusedSearchesSingleItem() async throws {
        let root = await makeRoot()

        let focusId = await root.itemController.addNew(type: .item)
        let otherId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Dragon Probe",   itemId: focusId)
        root.editController.reset(name: "Dragon Station", itemId: otherId)

        let (sut, _, _) = makeLinkSUT(for: root, focusId: focusId)
        let results = await sut.results(text: "Dragon")

        #expect(results.contains(where: { $0.itemId == focusId }),
                "Focused item must appear")
        #expect(!results.contains(where: { $0.itemId == otherId }),
                "Items outside focus must not appear even if their name matches")
    }

    // MARK: - resetDetail and detail search

    @Test("resetDetail creates a detailListModel scoped to the selected folder")
    func resetDetailCreatesDetailListModel() async throws {
        let root = await makeRoot()

        let folderId = await root.itemController.addNew(type: .folder)
        root.editController.reset(name: "Hangar Bay", itemId: folderId)
        let folder = root.itemController.itemOrEmpty(for: folderId)

        #expect(root.folderListControllable.listModel.detailListModel == nil,
                "Initially there must be no detailListModel")

        root.folderListControllable.resetDetail(model: folder)

        #expect(root.folderListControllable.listModel.detailListModel != nil,
                "resetDetail must create a detailListModel")
    }

    @Test("performDetailSearch populates detailListModel.list with the folder's direct children")
    func performDetailSearchPopulatesDetailList() async throws {
        let root = await makeRoot()

        let folderId = await root.itemController.addNew(type: .folder)
        let child1   = await root.itemController.addNew(type: .item)
        let child2   = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Hangar Bay", itemId: folderId)
        root.editController.reset(name: "Fighter",    itemId: child1)
        root.editController.reset(name: "Bomber",     itemId: child2)
        root.editController.addItem(itemId: child1, parentId: folderId)
        root.editController.addItem(itemId: child2, parentId: folderId)

        let folder = root.itemController.itemOrEmpty(for: folderId)
        root.folderListControllable.resetDetail(model: folder)
        await root.folderListControllable.performDetailSearch()

        let detailListModel = try #require(
            root.folderListControllable.listModel.detailListModel,
            "detailListModel must exist after resetDetail")

        let detailIds = detailListModel.list.map(\.source.itemId)
        #expect(detailIds.contains(child1), "Fighter must appear in detail list")
        #expect(detailIds.contains(child2), "Bomber must appear in detail list")
    }

    @Test("performDetailSearch excludes items that are not children of the selected folder")
    func performDetailSearchScopesToFolder() async throws {
        let root = await makeRoot()

        let folderId    = await root.itemController.addNew(type: .folder)
        let childId     = await root.itemController.addNew(type: .item)
        let unrelatedId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Fleet HQ", itemId: folderId)
        root.editController.reset(name: "Fighter",   itemId: childId)
        root.editController.reset(name: "Station",   itemId: unrelatedId)
        root.editController.addItem(itemId: childId, parentId: folderId)

        let folder = root.itemController.itemOrEmpty(for: folderId)
        root.folderListControllable.resetDetail(model: folder)
        await root.folderListControllable.performDetailSearch()

        let detailListModel = try #require(root.folderListControllable.listModel.detailListModel)
        let detailIds = detailListModel.list.map(\.source.itemId)

        #expect(detailIds.contains(childId),      "Folder child must appear in detail list")
        #expect(!detailIds.contains(unrelatedId), "Unrelated item must not appear in detail list")
        #expect(!detailIds.contains(folderId),    "Folder itself must not appear in its own detail list")
    }

    @Test("detailListModel.list is sorted alphabetically (folder children, empty search)")
    func performDetailSearchSortsChildrenAlphabetically() async throws {
        let root = await makeRoot()

        let folderId = await root.itemController.addNew(type: .folder)
        let idC = await root.itemController.addNew(type: .item)
        let idA = await root.itemController.addNew(type: .item)
        let idB = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Charlie", itemId: idC)
        root.editController.reset(name: "Alpha",   itemId: idA)
        root.editController.reset(name: "Bravo",   itemId: idB)
        root.editController.addItem(itemId: idC, parentId: folderId)
        root.editController.addItem(itemId: idA, parentId: folderId)
        root.editController.addItem(itemId: idB, parentId: folderId)

        let folder = root.itemController.itemOrEmpty(for: folderId)
        root.folderListControllable.resetDetail(model: folder)
        await root.folderListControllable.performDetailSearch()

        let detailListModel = try #require(root.folderListControllable.listModel.detailListModel)
        let names = detailListModel.list.map(\.source.itemId).compactMap {
            root.itemController.itemSync(for: $0)?.name
        }
        #expect(names == names.sorted { $0.localizedCompare($1) == .orderedAscending },
                "Detail list children must be sorted alphabetically")
    }

    @Test("Inspector folder mode returns hierarchical structure")
    func inspectorFolderModeReturnsHierarchy() async throws {
        let root = await makeRoot()

        let folderId = await root.itemController.addNew(type: .folder)
        let itemId   = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Dragon Dock",  itemId: folderId)
        root.editController.reset(name: "Dragon Scout", itemId: itemId)
        root.editController.addItem(itemId: itemId, parentId: folderId)

        let (sut, ldm, _) = makeLinkSUT(for: root, listMode: .list)

        // List mode: flat
        let listResults = await sut.results(text: "Dragon")
        if let folderFlat = listResults.first(where: { $0.itemId == folderId }) {
            #expect(folderFlat.children.isEmpty)
        }

        // Folder mode: nested
        ldm.listMode = .folder
        let folderResults = await sut.results(text: "Dragon")
        let folderResult  = try #require(folderResults.first(where: { $0.itemId == folderId }))
        #expect(folderResult.children.map(\.itemId).contains(itemId),
                "Inspector folder mode must nest the matching item inside the folder")
    }

    @Test("Fuzz: no sequence of folder operations lists a member twice")
    func fuzzNoDuplicateMembers() async throws {
        let root = await makeRoot()
        var folders: [UUID] = []
        var items: [UUID] = []
        for index in 0..<3 {
            let id = await root.itemController.addNew(type: .folder)
            root.editController.reset(name: "Folder \(index)", itemId: id)
            folders.append(id)
        }
        for index in 0..<4 {
            let id = await root.itemController.addNew(type: .item)
            root.editController.reset(name: "Item \(index)", itemId: id)
            items.append(id)
        }
        root.editController.addItem(itemId: folders[2], parentId: folders[0])

        var seed: UInt64 = 42
        func next(_ upper: Int) -> Int {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Int((seed >> 33) % UInt64(upper))
        }
        var log: [String] = []
        for step in 0..<400 {
            let all = items + folders
            let itemId = all[next(all.count)]
            switch next(5) {
            case 0, 1:
                let target = folders[next(folders.count)]
                log.append("add \(itemId.uuidString.prefix(4)) -> \(target.uuidString.prefix(4))")
                root.editController.addItem(itemId: itemId, parentId: target)
            case 2:
                if let parentId = root.itemController.itemSync(for: itemId)?.parentId {
                    let oneUp = next(2) == 0
                    log.append("remove \(itemId.uuidString.prefix(4)) from \(parentId.uuidString.prefix(4)) oneUp \(oneUp)")
                    root.editController.remove(itemId: itemId, parentId: parentId, oneUp: oneUp)
                }
            case 3:
                let target = folders[next(folders.count)]
                log.append("remove(stale) \(itemId.uuidString.prefix(4)) from \(target.uuidString.prefix(4))")
                root.editController.remove(itemId: itemId, parentId: target, oneUp: false)
            default:
                root.editController.repairFolders(itemIds: [itemId])
                log.append("repair \(itemId.uuidString.prefix(4))")
            }
            for folderId in folders {
                guard let folder = root.itemController.itemSync(for: folderId) else { continue }
                let children = folder.entries.map(\.childId)
                if Set(children).count != children.count {
                    Issue.record("duplicate member after step \(step): \(log.suffix(6))")
                    return
                }
            }
        }
    }

    // MARK: - Game delivery of a folder that already lists the member

    private func memberCount(_ folderId: UUID, of childId: UUID, in root: SpaceRootModel, noGame: Bool = true) -> Int {
        root.itemController.itemSync(for: folderId, noGame: noGame)?.entries.filter { $0.childId == childId }.count ?? -1
    }

    /// The receiver has folder P with member X; the sender's copy of P lists the same X under a
    /// different entry id (every Space add mints a new one).
    private func makeSharedFolder(_ root: SpaceRootModel) async throws -> (folderId: UUID, itemId: UUID, sender: SpaceModel) {
        let folderId = await root.itemController.addNew(type: .folder)
        let itemId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Ruines", itemId: folderId)
        root.editController.reset(name: "Item", itemId: itemId)
        root.editController.addItem(itemId: itemId, parentId: folderId)
        let local = try #require(root.itemController.itemSync(for: folderId, noGame: true))
        let sender = local.copy()
        sender.entries = [SpaceEntryModel(id: UUID(), spaceId: itemId)]
        #expect(sender.entries.first?.id != local.entries.first?.id)
        return (folderId, itemId, sender)
    }

    @Test("Game: merging the sender's copy of the folder into the library lists a member once")
    func gameLibraryMergeKeepsMemberOnce() async throws {
        let root = await makeRoot()
        let (folderId, itemId, sender) = try await makeSharedFolder(root)
        let merged = root.itemController.mergeSync(with: sender, forceMerge: true, noGame: true)
        if let merged { root.itemController.replaceImportedModel(model: merged, isInsert: true, forceSave: true) }
        #expect(memberCount(folderId, of: itemId, in: root) == 1)
    }

    @Test("Game: persisting a game-memory copy of the sender's folder lists a member once")
    func gamePersistKeepsMemberOnce() async throws {
        for authoritative in [false, true] {
            let root = await makeRoot()
            let (folderId, itemId, sender) = try await makeSharedFolder(root)
            root.itemController.replaceInGameMemory(model: sender)
            let gameCopy = try #require(root.itemController.itemSync(for: folderId))
            root.itemController.persistFromGame(model: gameCopy, authoritative: authoritative)
            #expect(memberCount(folderId, of: itemId, in: root) == 1, "authoritative: \(authoritative)")
        }
    }

    @Test("Game: a package import in game mode and the repair afterwards list a member once")
    func gameImportThenRepairKeepsMemberOnce() async throws {
        let root = await makeRoot()
        let (folderId, itemId, sender) = try await makeSharedFolder(root)
        root.itemController.itemDataModel.isGameMode = true
        // As `applyImportedItem` does in game mode: the delivery replaces the game-memory copy.
        root.itemController.replaceInGameMemory(model: sender)
        root.editController.repairFolders(itemIds: [folderId, itemId])
        #expect(memberCount(folderId, of: itemId, in: root, noGame: false) == 1, "game copy")
        #expect(memberCount(folderId, of: itemId, in: root, noGame: true) == 1, "library copy")
    }

    // MARK: - Duplicate folder members are healed

    @Test("Deduplicating keeps the smallest entry id per member and the order")
    func deduplicatedKeepsSmallestEntryId() {
        let childA = UUID(), childB = UUID()
        let low = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let high = UUID(uuidString: "FFFFFFFF-0000-0000-0000-000000000001")!
        let entries = [
            SpaceEntryModel(id: high, spaceId: childA),
            SpaceEntryModel(id: UUID(), spaceId: childB),
            SpaceEntryModel(id: low, spaceId: childA)
        ]
        let unique = FolderEntryMerge.deduplicated(entries, id: \.id, childId: \.childId)
        #expect(unique?.map(\.childId) == [childB, childA])
        #expect(unique?.last?.id == low)
        #expect(FolderEntryMerge.deduplicated(unique ?? [], id: \.id, childId: \.childId) == nil)
    }

    @Test("A synced folder carrying a member twice lists it once")
    func syncedDuplicateMemberIsHealed() async throws {
        let root = await makeRoot()
        let (folderId, itemId, sender) = try await makeSharedFolder(root)
        // Both rows reach this device, as CloudKit unions them.
        let synced = try #require(root.itemController.itemSync(for: folderId, noGame: true)).copy()
        synced.entries.append(contentsOf: sender.entries)
        #expect(synced.entries.filter { $0.childId == itemId }.count == 2)
        root.itemController.applyMergedUpdate(model: synced)
        #expect(memberCount(folderId, of: itemId, in: root) == 1)
    }

    @Test("A loaded folder with a member twice is healed")
    func loadedDuplicateMemberIsHealed() async throws {
        let root = await makeRoot()
        let (folderId, itemId, sender) = try await makeSharedFolder(root)
        let folder = try #require(root.itemController.itemSync(for: folderId, noGame: true))
        folder.entries.append(contentsOf: sender.entries)
        #expect(memberCount(folderId, of: itemId, in: root) == 2)
        #expect(root.itemController.healDuplicateFolderMembers(itemId: folderId))
        #expect(memberCount(folderId, of: itemId, in: root) == 1)
        #expect(!root.itemController.healDuplicateFolderMembers(itemId: folderId))
    }

    @Test("Repairing folders removes a duplicate member")
    func repairRemovesDuplicateMember() async throws {
        let root = await makeRoot()
        let (folderId, itemId, sender) = try await makeSharedFolder(root)
        let folder = try #require(root.itemController.itemSync(for: folderId, noGame: true))
        folder.entries.append(contentsOf: sender.entries)
        root.editController.repairFolders(itemIds: [folderId])
        #expect(memberCount(folderId, of: itemId, in: root) == 1)
    }
}
