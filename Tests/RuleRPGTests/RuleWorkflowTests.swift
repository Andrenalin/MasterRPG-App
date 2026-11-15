// @copyright André Trettin

#if canImport(Testing)
@testable import CoreRPG
import Foundation
import Testing

@testable import PhotoRPG
@testable import RuleRPG

@Suite("Rule workflows")
@MainActor
struct RuleWorkflowTests {
    @Test("GMZ export and import preserve rules, links, and Foundry payloads")
    func importExportRoundTrip() async throws {
        // Given
        let source = RuleRootModel.testRoot()
        let linkedID = try #require(UUID(uuidString: "D7EF4617-9B67-481D-9714-E5DFEBC3074D"))
        let sourceID = try #require(UUID(uuidString: "1E6B2309-4CF4-4BB8-B791-F1EE6AAC89ED"))
        let linked = RuleModel.fixture(
            id: linkedID,
            name: "Linked Rule",
            entries: [.fixture(name: "Result", content: "Linked content")]
        )
        source.itemController.replace(model: linked, isInsert: true)
        let link = source.linkController.generateLink(linkNumber: 0, itemId: linkedID, entryId: nil)
        let rawData: FoundryJSONValue = .object([
            "_id": .string("source-rule"),
            "system": .object(["link": .string(link)])
        ])
        let rule = RuleModel.fixture(
            id: sourceID,
            name: "Source Rule",
            entries: [.fixture(name: "Related", content: link, kind: .reference)],
            sourceMetadata: RuleSourceMetadata(
                sourceIdentifier: "source-rule",
                systemID: "ds4",
                packageIdentifier: "ds4.rules"
            ),
            sourcePayload: .foundryDocument(rawData)
        )
        source.itemController.replace(model: rule, isInsert: true)
        let exportIDs = source.exportController.exporting(
            itemIds: ItemModuleIds(ids: [sourceID], module: .rule)
        )

        // When
        #expect(Set(exportIDs.ids[.rule, default: []]) == Set([sourceID, linkedID]))
        let output = OutputStream.toMemory()
        output.open()
        defer { output.close() }
        // The owner export (file export and Save Game) keeps the Foundry payload; the stream
        // overload without a model builds packages for the other players of a game.
        _ = try await source.exportController.export(
            itemIds: exportIDs,
            into: output,
            exportModel: ItemDataExportModel()
        )
        let data = try #require(
            output.property(forKey: .dataWrittenToMemoryStreamKey) as? Data
        )

        let destination = RuleRootModel.testRoot()
        let input = InputStream(data: data)
        input.open()
        defer { input.close() }
        try await destination.importController.importStream(from: input, forceSave: false)

        // Then
        #expect(Set(destination.itemController.itemDataModel.items) == [sourceID, linkedID])
        let imported = try #require(destination.itemController.itemSync(for: sourceID))
        #expect(imported.name == rule.name)
        #expect(imported.entries == rule.entries)
        #expect(imported.sourceMetadata == rule.sourceMetadata)
        #expect(imported.sourcePayload == rule.sourcePayload)
        #expect(destination.linkController.collectLinks(of: .rule, from: sourceID) == [linkedID])
    }

    @Test("A package for players leaves out the raw Foundry payload but keeps the version")
    func playerPackageDropsSourcePayload() async throws {
        // Given
        let source = RuleRootModel.testRoot()
        let sourceID = try #require(UUID(uuidString: "5B0C2F7A-1D34-4E0B-9E6F-3B1A7C2D9E41"))
        let rule = RuleModel.fixture(
            id: sourceID,
            name: "Payload Rule",
            entries: [.fixture(name: "Result", content: "Content")],
            sourcePayload: .foundryDocument(.object(["_id": .string("payload-rule")]))
        )
        source.itemController.replace(model: rule, isInsert: true)
        let exportIDs = source.exportController.exporting(
            itemIds: ItemModuleIds(ids: [sourceID], module: .rule)
        )
        let output = OutputStream.toMemory()
        output.open()
        defer { output.close() }

        // When
        _ = try await source.exportController.export(itemIds: exportIDs, into: output)
        let data = try #require(output.property(forKey: .dataWrittenToMemoryStreamKey) as? Data)
        let destination = RuleRootModel.testRoot()
        let input = InputStream(data: data)
        input.open()
        defer { input.close() }
        try await destination.importController.importStream(from: input, forceSave: false)

        // Then
        let imported = try #require(destination.itemController.itemSync(for: sourceID))
        #expect(imported.sourcePayload == nil)
        #expect(imported.name == rule.name)
        // The version does not depend on the payload, so a copy without it agrees with the master.
        let withoutPayload = rule.copy()
        withoutPayload.sourcePayload = nil
        #expect(withoutPayload.version == rule.version)
    }

    @Test("Search excludes hidden rules and folder scope exposes visible children")
    func searchAndFolderBehavior() async throws {
        // Given
        let root = RuleRootModel.testRoot()
        let childID = try #require(UUID(uuidString: "5272B5B6-702F-4827-84DA-124994B31C01"))
        let hiddenID = try #require(UUID(uuidString: "4AACB4CC-7BC5-4D25-9F29-1E609AB8F629"))
        let folderID = try #require(UUID(uuidString: "62DE2EAE-306D-436D-B10F-E006618CAFE2"))
        let child = RuleModel.fixture(
            id: childID,
            name: "Arcane Shield",
            description: "Visible defensive rule",
            parentId: folderID
        )
        let hidden = RuleModel.fixture(
            id: hiddenID,
            name: "Arcane Secret",
            displayState: DisplayStateMask.groupHidden.rawValue
        )
        let folder = RuleModel.fixture(
            id: folderID,
            name: "Defensive Rules",
            category: .folder,
            entries: [RuleEntryModel(id: childID, name: child.name, content: "")]
        )
        root.itemController.replace(model: child, isInsert: true)
        root.itemController.replace(model: hidden, isInsert: true)
        root.itemController.replace(model: folder, isInsert: true)

        // When
        let globalResults = await root.searchController.globalSearchResults(searchText: "Arcane")
        let folderResults = await root.folderListController.searchRootControllable.scopedResults(
            text: "",
            focusId: folderID
        )
        let expanded = root.folderListController.searchRootControllable.syncExpandResults(
            focusId: folderID
        )
        let expandedChild = try #require(expanded.first)

        // Then
        #expect(globalResults.map(\.itemId) == [childID])
        #expect(folderResults.map(\.itemId) == [childID])
        #expect(expanded.map(\.itemId) == [childID])
        #expect(expandedChild.module == .rule)
        #expect(!expandedChild.canOpen)
    }

    @Test("Description and entry links are collected and broken description links are repaired")
    func descriptionLinkCollectionAndRepair() throws {
        // Given
        let root = RuleRootModel.testRoot()
        let sourceID = try #require(UUID(uuidString: "2E8E7A38-27AB-4858-8D01-0F550A2E84EB"))
        let descriptionTargetID = try #require(UUID(uuidString: "ECBFBEBA-9731-4B35-B757-913B58FF2CA1"))
        let entryTargetID = try #require(UUID(uuidString: "A1D235D0-D457-4FB8-A518-49803F4B1FF8"))
        let missingTargetID = try #require(UUID(uuidString: "78FC0296-47DD-4D0B-89D5-E84614861820"))
        root.itemController.replace(
            model: RuleModel.fixture(id: descriptionTargetID, name: "Description Target"),
            isInsert: true
        )
        root.itemController.replace(
            model: RuleModel.fixture(id: entryTargetID, name: "Entry Target"),
            isInsert: true
        )
        let descriptionLink = LinkRuleData(
            itemId: descriptionTargetID,
            name: "Description Target"
        ).linkRepresentation
        let missingLink = LinkRuleData(
            itemId: missingTargetID,
            name: "Missing Target"
        ).linkRepresentation
        let entryLink = LinkRuleData(
            itemId: entryTargetID,
            name: "Entry Target"
        ).linkRepresentation
        root.itemController.replace(
            model: RuleModel.fixture(
                id: sourceID,
                name: "Source",
                description: "\(descriptionLink) \(missingLink)",
                entries: [.fixture(name: "Related", content: entryLink)]
            ),
            isInsert: true
        )

        // When
        let linksBeforeRepair = Set(root.linkController.collectLinks(of: .rule, from: sourceID))
        root.linkController.validateLinks(on: sourceID)
        let repaired = try #require(root.itemController.itemSync(for: sourceID))
        let linksAfterRepair = Set(root.linkController.collectLinks(of: .rule, from: sourceID))

        // Then
        #expect(linksBeforeRepair == [descriptionTargetID, entryTargetID, missingTargetID])
        #expect(repaired.description.contains(descriptionTargetID.uuidString))
        #expect(!repaired.description.contains(missingTargetID.uuidString))
        #expect(repaired.description.contains("Missing Target"))
        #expect(linksAfterRepair == [descriptionTargetID, entryTargetID])
    }

    @Test("Folder exports include children and partial ancestors are represented")
    func folderExportBehavior() throws {
        // Given
        let root = RuleRootModel.testRoot()
        let folderID = try #require(UUID(uuidString: "0489EEBB-5907-4399-9147-A0A6D82C1689"))
        let firstID = try #require(UUID(uuidString: "8D576342-F17E-4A88-90B7-950747C93AC2"))
        let secondID = try #require(UUID(uuidString: "EA75EA9B-F201-460E-9CDD-D2EB930181A1"))
        let first = RuleModel.fixture(id: firstID, name: "First", parentId: folderID)
        let second = RuleModel.fixture(id: secondID, name: "Second", parentId: folderID)
        let folder = RuleModel.fixture(
            id: folderID,
            name: "Folder",
            category: .folder,
            entries: [
                RuleEntryModel(id: firstID, name: first.name, content: ""),
                RuleEntryModel(id: secondID, name: second.name, content: "")
            ]
        )
        root.itemController.replace(model: first, isInsert: true)
        root.itemController.replace(model: second, isInsert: true)
        root.itemController.replace(model: folder, isInsert: true)

        // When
        let fullFolder = root.exportController.exporting(
            itemIds: ItemModuleIds(ids: [folderID], module: .rule)
        )
        let partialFolder = root.exportController.exporting(
            itemIds: ItemModuleIds(ids: [firstID], module: .rule)
        )

        // Then
        #expect(Set(fullFolder.ids[.rule, default: []]) == Set([folderID, firstID, secondID]))
        #expect(Set(partialFolder.ids[.rule, default: []]) == Set([firstID]))
        #expect(Set(partialFolder.partialIds[.rule, default: []]) == Set([folderID]))
    }

    @Test("Rule export follows description links, expands leaf modules, and bounds Rule cycles")
    func linkedModuleExportBehavior() async throws {
        // Given
        let root = RuleRootModel.testRoot()
        let photoRoot = PhotoRootModel.testRoot()
        let rootManager = RootManager(
            adventureRoot: root,
            audioRoot: root,
            characterRoot: root,
            diceRoot: root,
            generatorRoot: root,
            mapRoot: root,
            pdfRoot: root,
            photoRoot: photoRoot,
            ruleRoot: root,
            spaceRoot: root,
            tableRoot: root,
            weatherRoot: root
        )
        root.setUp(
            context: nil,
            rootManager: rootManager,
            adventureRootControllable: root,
            linkRegisterController: LinkRegisterController(root: rootManager)
        )

        let firstRuleID = try #require(UUID(uuidString: "337B5E64-0706-455F-9ED9-66F63C13A174"))
        let secondRuleID = try #require(UUID(uuidString: "96F52020-18A7-49EF-99DF-945469228CC5"))
        let adventureID = try #require(UUID(uuidString: "FA4AA29B-DB79-461D-99F8-48EAC035F711"))
        let missingPhotoID = try #require(UUID(uuidString: "84944898-FC86-43F2-866B-A2BF260A68A1"))
        let photoID = await photoRoot.itemController.addNew(type: .item)
        let referencedPhotoID = await photoRoot.itemController.addNew(type: .item)
        let photo = photoRoot.itemController.itemOrEmpty(for: photoID)
        photo.entries.append(PhotoEntryModel(id: UUID(), photoId: referencedPhotoID))
        photoRoot.itemController.replace(model: photo, isInsert: false)

        // The test RootManager uses the Rule root as its lightweight Adventure validator.
        root.itemController.replace(
            model: RuleModel.fixture(id: adventureID, name: "Adventure destination"),
            isInsert: true
        )
        let photoLink = LinkPhotoData(itemId: photoID, name: "Portrait").linkRepresentation
        let missingPhotoLink = LinkPhotoData(
            itemId: missingPhotoID,
            name: "Missing portrait"
        ).linkRepresentation
        let adventureLink = LinkAdventureData(
            itemId: adventureID,
            name: "Encounter"
        ).linkRepresentation
        let firstRuleLink = LinkRuleData(itemId: firstRuleID, name: "First Rule").linkRepresentation
        let secondRuleLink = LinkRuleData(itemId: secondRuleID, name: "Second Rule").linkRepresentation
        let firstRule = RuleModel.fixture(
            id: firstRuleID,
            name: "First Rule",
            description: "\(photoLink) \(missingPhotoLink) \(adventureLink)",
            entries: [.fixture(name: "Next", content: secondRuleLink, kind: .reference)]
        )
        let secondRule = RuleModel.fixture(
            id: secondRuleID,
            name: "Second Rule",
            description: firstRuleLink
        )
        root.itemController.replace(model: firstRule, isInsert: true)
        root.itemController.replace(model: secondRule, isInsert: true)

        // When
        let exported = root.exportController.exporting(
            itemIds: ItemModuleIds(ids: [firstRuleID], module: .rule)
        )

        // Then
        #expect(Set(exported.ids[.rule, default: []]) == Set([firstRuleID, secondRuleID]))
        #expect(Set(exported.ids[.photo, default: []]) == Set([photoID, referencedPhotoID]))
        #expect(Set(exported.ids[.adventure, default: []]) == [adventureID])
    }
}
#endif
