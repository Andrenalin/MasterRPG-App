// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import Testing

@testable import RuleRPG

@Suite("Rule entry tree")
@MainActor
struct RuleEntryTreeTests {
    @Test("Tree nests group children and safely promotes malformed parents")
    func hierarchyProjection() {
        let group = entry(name: "Attributes", kind: .group)
        let childGroup = entry(name: "Body", kind: .group, parentID: group.id)
        let leaf = entry(name: "Base", content: "5", parentID: childGroup.id)
        let orphan = entry(name: "Orphan", parentID: UUID())
        let cycleA = entry(name: "Cycle A", kind: .group)
        let cycleB = entry(name: "Cycle B", kind: .group, parentID: cycleA.id)
        let cycleChild = entry(name: "Cycle Child", parentID: cycleA.id)
        var cyclicA = cycleA
        cyclicA.parentId = cycleB.id

        let tree = RuleEntryTree(entries: [
            group,
            childGroup,
            leaf,
            orphan,
            cyclicA,
            cycleB,
            cycleChild
        ])

        #expect(tree.roots.map(\.id) == [group.id, orphan.id, cycleA.id, cycleB.id])
        #expect(tree.roots[0].children.map(\.id) == [childGroup.id])
        #expect(tree.roots[0].children[0].children.map(\.id) == [leaf.id])
        #expect(tree.roots[2].children.map(\.id) == [cycleChild.id])
    }

    @Test("Parent choices exclude the entry and every descendant")
    func validParentChoices() {
        let root = entry(name: "Root", kind: .group)
        let child = entry(name: "Child", kind: .group, parentID: root.id)
        let grandchild = entry(name: "Grandchild", parentID: child.id)
        let unrelated = entry(name: "Unrelated", kind: .group)
        let entries = [root, child, grandchild, unrelated]

        let rootChoices = RuleEntryTree.validParentGroups(for: root.id, in: entries)
        let childChoices = RuleEntryTree.validParentGroups(for: child.id, in: entries)

        #expect(rootChoices.map(\.id) == [unrelated.id])
        #expect(childChoices.map(\.id) == [root.id, unrelated.id])
        #expect(
            RuleEntryTree.settingParent(
                child.id,
                for: root.id,
                in: entries
            ) == entries
        )
    }

    @Test("Changing a group to a leaf reparents direct children to its parent")
    func groupToLeafIntegrity() {
        let root = entry(name: "Root", kind: .group)
        let group = entry(name: "Body", kind: .group, parentID: root.id)
        let firstChild = entry(name: "Base", content: "5", parentID: group.id)
        let nestedGroup = entry(name: "Derived", kind: .group, parentID: group.id)
        let nestedLeaf = entry(name: "Defense", content: "8", parentID: nestedGroup.id)

        let updated = RuleEntryTree.settingKind(
            .text,
            for: group.id,
            in: [root, group, firstChild, nestedGroup, nestedLeaf]
        )

        #expect(updated.first(where: { $0.id == group.id })?.kind == .text)
        #expect(updated.first(where: { $0.id == firstChild.id })?.parentId == root.id)
        #expect(updated.first(where: { $0.id == nestedGroup.id })?.parentId == root.id)
        #expect(updated.first(where: { $0.id == nestedLeaf.id })?.parentId == nestedGroup.id)
    }

    @Test("Deleting a group removes its complete subtree")
    func groupDeletionIntegrity() {
        let rootLeaf = entry(name: "Introduction")
        let group = entry(name: "Attributes", kind: .group)
        let childGroup = entry(name: "Body", kind: .group, parentID: group.id)
        let leaf = entry(name: "Base", content: "5", parentID: childGroup.id)

        let remaining = RuleEntryTree.removingEntries(
            at: IndexSet(integer: 1),
            from: [rootLeaf, group, childGroup, leaf]
        )

        #expect(remaining == [rootLeaf])
    }

    @Test("Sheet projection uses group rows and retains linked rule sheets")
    func sheetProjection() throws {
        let root = RuleRootModel.testRoot()
        let rootManager = RootManager(anyRoot: root)
        let itemID = UUID()
        let linkedRuleID = UUID()
        let group = entry(name: "Attributes", kind: .group)
        let leaf = entry(name: "Base", content: "5", parentID: group.id)
        let link = root.linkController.generateLink(
            linkNumber: 0,
            itemId: linkedRuleID,
            entryId: nil
        )
        let linkedLeaf = entry(name: "See Also", content: link)

        root.itemController.replace(
            model: RuleModel.fixture(
                id: linkedRuleID,
                name: "Linked Rule",
                entries: [.fixture(name: "Linked Content")]
            ),
            isInsert: true
        )
        root.itemController.replace(
            model: RuleModel.fixture(
                id: itemID,
                name: "Source Rule",
                entries: [group, leaf, linkedLeaf]
            ),
            isInsert: true
        )

        let controller = SheetController(itemController: root.itemController)
        let sheet = controller.sheet(
            root: rootManager,
            itemId: itemID,
            destination: nil,
            level: 0,
            isShown: true,
            moduleDepth: 0,
            isEditor: false
        )
        let groupSheet = try #require(sheet.entries.first)
        let leafSheet = try #require(groupSheet.entries.first)
        let linkedLeafSheet = try #require(sheet.entries.last)
        let linkedRuleSheet = try #require(linkedLeafSheet.entries.first)

        #expect(sheet.entries.map(\.source.entryId) == [group.id, linkedLeaf.id])
        #expect(groupSheet.sheetType == .group)
        #expect(groupSheet.level == 0)
        #expect(leafSheet.source.entryId == leaf.id)
        #expect(leafSheet.sheetType == .item)
        #expect(leafSheet.level == 1)
        #expect(linkedRuleSheet.source.itemId == linkedRuleID)
        #expect(linkedRuleSheet.source.entryId == nil)
        #expect(linkedRuleSheet.level == 1)
        #expect(linkedRuleSheet.isFolded)

        groupSheet.isShown = false
        let item = root.itemController.itemOrEmpty(for: itemID)
        var updatedEntries = item.entries
        let leafIndex = try #require(updatedEntries.firstIndex(where: { $0.id == leaf.id }))
        updatedEntries[leafIndex].content = "6"
        item.entries = updatedEntries

        controller.update(root: rootManager, sheetModel: sheet, isEditor: false)

        let updatedGroupSheet = try #require(sheet.entries.first)
        let updatedLeafSheet = try #require(updatedGroupSheet.entries.first)
        #expect(updatedGroupSheet === groupSheet)
        #expect(!updatedGroupSheet.isShown)
        #expect(updatedLeafSheet.description == "6")
    }

    private func entry(
        name: String,
        content: String = "",
        kind: RuleEntryKind = .text,
        parentID: UUID? = nil
    ) -> RuleEntryModel {
        var entry = RuleEntryModel(
            id: UUID(),
            name: name,
            content: content,
            kind: kind
        )
        entry.parentId = parentID
        return entry
    }
}
#endif
