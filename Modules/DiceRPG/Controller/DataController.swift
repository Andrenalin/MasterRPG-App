// @copyright André Trettin

import CoreRPG
import Foundation
import CoreData

struct DataController: DataPersistenceControllable {
    @MainActor init(context: NSManagedObjectContext, batchContext: NSManagedObjectContext? = nil, token: String) {
            self.dataController = CoreDataController<DiceModel, RPGDice>(context: context, batchContext: batchContext, relationshipKeyPaths: ["entries"])
            self.token = token
        }
        
        let dataController: CoreDataController<DiceModel, RPGDice>
        let token: String
}

extension DataController: CoreDataSnapshotPersistable {
    // MARK: managed object -> snapshot (context queue)

    @Sendable
    func mapSnapshot(_ model: RPGDice, token: String) -> DiceSnapshot {
        DiceSnapshot(
            id: model.uuid ?? UUID(),
            name: CRDT(wrappedValue: model.name ?? ""),
            description: CRDT(wrappedValue: model.information ?? ""),
            tags: CRDT(string: model.tags ?? "", defaultValue: tags(from: model.tags)),
            category: CRDT(string: model.diceCategory ?? "", defaultValue: ItemListCategory.rules),
            displayState: Int(model.displayState),
            dice: CRDTDataUpdate(wrappedValue: dice(from: model.dice), update: CRDT(string: model.diceUpdate ?? "", defaultValue: UUID())),
            sumUp: model.sumUp,
            modifier: Double(model.modifier),
            percentDice: model.percentDice,
            compareOption: DiceModel.CompareValue(rawValue: Int(model.compareOption)) ?? .off,
            compareValue: Double(model.compareValue),
            coupValues: coupFumble(from: model.coupValues),
            coupOnlyOnFirstDie: model.coupOnlyOnFirstDie,
            fumbleValues: coupFumble(from: model.fumbleValues),
            fumbleOnlyOnFirstDie: model.fumbleOnlyOnFirstDie,
            rerollOptions: rerollOptions(from: model.rerollOptions),
            reorderDice: model.reorderDice,
            addDiceEvery: Int(model.addDiceEvery),
            entries: CRDTDataUpdate(wrappedValue: model.entriesModel.map { map($0) }, update: CRDT(string: model.entriesUpdate ?? "", defaultValue: UUID())),
            parentId: model.parentId
        )
    }

    // MARK: snapshot -> managed object (context queue)
    
    @Sendable
    func applySnapshot(_ snapshot: DiceSnapshot, into model: RPGDice) {
        model.uuid <=> snapshot.id
        model.name <=> snapshot.name_.rawValue
        model.information <=> snapshot.description_.rawValue
        model.tags <=> snapshot.tags_.rawValue
        model.diceCategory <=> snapshot.category_.rawValue
        model.displayState <=> Int32(snapshot.displayState)
        unequalSet(lhs: &model.diceUpdate, rhs: snapshot.dice_.$update.rawValue) {
            model.dice = snapshot.dice.map { $0.die.text }.joined(separator: ",")
        }
        model.sumUp <=> snapshot.sumUp
        model.modifier <=> Float(snapshot.modifier)
        model.percentDice <=> snapshot.percentDice
        model.compareOption <=> Int16(snapshot.compareOption.rawValue)
        model.compareValue <=> Float(snapshot.compareValue)
        model.coupValues <=> snapshot.coupValues.map { $0.rawValue }.joined(separator: ",")
        model.coupOnlyOnFirstDie <=> snapshot.coupOnlyOnFirstDie
        model.fumbleValues <=> snapshot.fumbleValues.map { $0.rawValue }.joined(separator: ",")
        model.fumbleOnlyOnFirstDie <=> snapshot.fumbleOnlyOnFirstDie
        model.rerollOptions <=> snapshot.rerollOptions.map { "\($0.number)/\($0.value)/\($0.maxDiceValue ? "1" : "0")" }.joined(separator: ",")
        model.reorderDice <=> snapshot.reorderDice
        model.addDiceEvery <=> Int16(snapshot.addDiceEvery)
        unequalSet(lhs: &model.entriesUpdate, rhs: snapshot.entries_.$update.rawValue) {
            model.entriesModel = model.syncEntries(
                incoming: snapshot.entries,
                current: model.entriesModel,
                childId: { $0.id },
                map: { self.map($0, into: $1, index: $2) }
            )
        }
        model.parentId <=> snapshot.parentId
    }


    // MARK: model <-> snapshot (MainActor)

    @MainActor
    func makeModel(from snapshot: DiceSnapshot) -> DiceModel {
        snapshot.makeModel()
    }

    @MainActor
    func makeSnapshot(from model: DiceModel) -> DiceSnapshot {
        DiceSnapshot(model)
    }

    // MARK: - other mappers
    
    private func coupFumble(from model: String?) -> [DiceModel.CoupFumbleOption] {
        guard let model else { return [] }

        return model.components(separatedBy: ",").compactMap {
            let value = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            return DiceModel.CoupFumbleOption(rawValue: value)
        }
    }

    private func rerollOptions(from model: String?) -> [DiceModel.RerollOption] {
        guard let model else { return [] }

        return model.components(separatedBy: ",").compactMap {
            let comp = $0.split(separator: "/")
            guard comp.count == 3 else { return nil }
            let reroll = DiceModel.RerollOption(number: Int(comp[0]) ?? 0, value: Int(comp[1]) ?? 0, maxDiceValue: comp[2] == "1")
            if reroll.number > 0 {
                return reroll
            }
            return nil
        }
    }

    private func dice(from model: String?) -> [DieModel] {
        guard let model else { return [] }

        return model.components(separatedBy: ",").compactMap {
            let die = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            if die.isEmpty {
                return nil
            }
            return DieModel(id: UUID(), die: RawDie(text: $0))
        }
    }
    
    // MARK: - ChildEntryViewModel

    private func map(_ model: RPGDiceEntry) -> ChildEntryModel {
        ChildEntryModel(
            id: model.uuid ?? UUID(),
            childId: (model.childUUID ?? model.uuid ?? UUID())
        )
    }

    private func map(_ viewModel: ChildEntryModel, into entry: RPGDiceEntry, index: Int) {
        entry.uuid = viewModel.id
        entry.childUUID = viewModel.childId
        entry.index = Int16(index)
    }
}
