// @copyright André Trettin

import CoreData
import CoreRPG
import Foundation

struct DataController: DataPersistenceControllable {
    @MainActor
    init(
        context: NSManagedObjectContext,
        batchContext: NSManagedObjectContext? = nil,
        token: String
    ) {
        dataController = CoreDataController<RuleModel, RPGRule>(
            context: context,
            batchContext: batchContext,
            relationshipKeyPaths: ["entries"]
        )
        self.token = token
    }

    let dataController: CoreDataController<RuleModel, RPGRule>
    let token: String
}

extension DataController: CoreDataSnapshotPersistable {
    @Sendable
    func mapSnapshot(_ model: RPGRule, token: String) -> RuleSnapshot {
        RuleSnapshot(
            id: model.uuid ?? UUID(),
            name: CRDT(wrappedValue: model.name ?? ""),
            description: CRDT(wrappedValue: model.information ?? ""),
            tags: CRDT(string: model.tags ?? "", defaultValue: []),
            category: CRDT(
                string: model.ruleCategory ?? "",
                defaultValue: ItemListCategory.rules
            ),
            displayState: Int(model.displayState),
            entries: CRDTDataUpdate(
                wrappedValue: model.entriesModel.map(map),
                update: CRDT(string: model.entriesUpdate ?? "", defaultValue: UUID())
            ),
            sourceMetadata: CRDT(
                string: model.sourceMetadata ?? "",
                defaultValue: .empty
            ),
            sourcePayload: CRDT(
                string: model.sourcePayload ?? "",
                defaultValue: nil
            ),
            parentId: model.parentId
        )
    }

    @Sendable
    func applySnapshot(_ snapshot: RuleSnapshot, into model: RPGRule) {
        model.uuid <=> snapshot.id
        model.name <=> snapshot.name.rawValue
        model.information <=> snapshot.description.rawValue
        model.tags <=> snapshot.tags.rawValue
        model.ruleCategory <=> snapshot.category.rawValue
        model.displayState <=> Int32(snapshot.displayState)
        model.sourceMetadata <=> snapshot.sourceMetadata.rawValue
        model.sourcePayload <=> snapshot.sourcePayload.rawValue
        unequalSet(lhs: &model.entriesUpdate, rhs: snapshot.entries.$update.rawValue) {
            let oldEntries = model.entriesModel
            let newEntries = snapshot.entries.wrappedValue.enumerated().map { index, entry in
                let managedEntry = model.entryOrNew(for: entry.id)
                map(entry, into: managedEntry, index: index)
                return managedEntry
            }
            model.entriesModel = newEntries

            let retained = Set(newEntries.map(ObjectIdentifier.init))
            for entry in oldEntries where !retained.contains(ObjectIdentifier(entry)) {
                model.managedObjectContext?.delete(entry)
            }
        }
        model.parentId <=> snapshot.parentId
    }

    @MainActor
    func makeModel(from snapshot: RuleSnapshot) -> RuleModel {
        snapshot.makeModel()
    }

    @MainActor
    func makeSnapshot(from model: RuleModel) -> RuleSnapshot {
        RuleSnapshot(model)
    }

    private func map(_ model: RPGRuleEntry) -> RuleEntryModel {
        RuleEntryModel(
            id: model.uuid ?? UUID(),
            name: model.name ?? "",
            content: model.content ?? "",
            kind: RuleEntryKind(rawValue: model.kind ?? "") ?? .text,
            displayState: Int(model.displayState)
        )
    }

    private func map(_ entry: RuleEntryModel, into model: RPGRuleEntry, index: Int) {
        model.uuid = entry.id
        model.name = entry.name
        model.content = entry.content
        model.kind = entry.kind.rawValue
        model.displayState = Int32(entry.displayState)
        model.index = Int32(index)
    }
}
