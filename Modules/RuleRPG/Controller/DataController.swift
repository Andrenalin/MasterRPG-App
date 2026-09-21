// @copyright André Trettin

import CoreData
import CoreRPG
import Foundation

struct DataController: DataPersistenceControllable {
    @MainActor
    init(
        context: NSManagedObjectContext,
        token: String
    ) {
        dataController = CoreDataController<RuleModel, RPGRule>(
            context: context,
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
        model.displayState <=> Int32(clamping: snapshot.displayState)
        model.sourceMetadata <=> snapshot.sourceMetadata.rawValue
        model.sourcePayload <=> snapshot.sourcePayload.rawValue
        // Uses the shared `syncEntries` helper instead of hand-rolling the find-or-new +
        // diff + delete-orphans pattern (CODE_AUDIT §9.3) — the same duplicated block that
        // GeneratorRPG's copy silently lost the delete step from (see CODE_AUDIT §5.4).
        unequalSet(lhs: &model.entriesUpdate, rhs: snapshot.entries.$update.rawValue) {
            model.entriesModel = model.syncEntries(
                incoming: snapshot.entries.wrappedValue,
                current: model.entriesModel,
                childId: { $0.id },
                map: { self.map($0, into: $1, index: $2) }
            )
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
            displayState: Int(model.displayState),
            parentId: model.parentId
        )
    }

    private func map(_ entry: RuleEntryModel, into model: RPGRuleEntry, index: Int) {
        model.uuid = entry.id
        model.name = entry.name
        model.content = entry.content
        model.kind = entry.kind.rawValue
        model.displayState = Int32(clamping: entry.displayState)
        model.parentId = entry.parentId
        model.index = Int32(clamping: index)
    }
}
