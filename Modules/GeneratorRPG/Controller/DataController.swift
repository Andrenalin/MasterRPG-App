// @copyright André Trettin

import AndrenalinKit
import Foundation
import CoreData

struct DataController: DataPersistenceControllable {
    @MainActor init(context: NSManagedObjectContext, token: String) {
            self.dataController = CoreDataController<DiceModel, RPGDice>(context: context)
            self.token = token
        }
        
        let dataController: CoreDataController<DiceModel, RPGDice>
        let token: String
}

extension DataController: CoreDataPersistable {
    // MARK: model -> viewlmodel

    func mapViewModel(_ model: RPGDice, token: String) -> DiceModel {
        DiceModel(
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
            rerollOptions: reroleOptions(from: model.rerollOptions),
            reorderDice: model.reorderDice,
            addDiceEvery: Int(model.addDiceEvery),
            entries: CRDTDataUpdate(wrappedValue: model.entriesModel.map { map($0) }, update: CRDT(string: model.entriesUpdate ?? "", defaultValue: UUID())),
            parentId: model.parentId
        )
    }

    // MARK: viewmodel -> model
    
    func mapModel(_ viewModel: DiceModel, into model: RPGDice) {
        model.uuid <=> viewModel.id
        model.name <=> viewModel.name_.rawValue
        model.information <=> viewModel.description_.rawValue
        model.tags <=> viewModel.tags_.rawValue
        model.diceCategory <=> viewModel.category_.rawValue
        model.displayState <=> Int32(viewModel.displayState)
        unequalSet(lhs: &model.diceUpdate, rhs: viewModel.dice_.$update.rawValue) {
            model.dice = viewModel.dice.map { $0.die.text }.joined(separator: ",")
        }
        model.sumUp <=> viewModel.sumUp
        model.modifier <=> Float(viewModel.modifier)
        model.percentDice <=> viewModel.percentDice
        model.compareOption <=> Int16(viewModel.compareOption.rawValue)
        model.compareValue <=> Float(viewModel.compareValue)
        model.coupValues <=> viewModel.coupValues.map { $0.rawValue }.joined(separator: ",")
        model.coupOnlyOnFirstDie <=> viewModel.coupOnlyOnFirstDie
        model.fumbleValues <=> viewModel.fumbleValues.map { $0.rawValue }.joined(separator: ",")
        model.fumbleOnlyOnFirstDie <=> viewModel.fumbleOnlyOnFirstDie
        model.rerollOptions <=> viewModel.rerollOptions.map { "\($0.number)/\($0.value)/\($0.maxDiceValue ? "1" : "0")" }.joined(separator: ",")
        model.reorderDice <=> viewModel.reorderDice
        model.addDiceEvery <=> Int16(viewModel.addDiceEvery)
        unequalSet(lhs: &model.entriesUpdate, rhs: viewModel.entries_.$update.rawValue) {
            model.entriesModel = viewModel.entries.enumerated().map {
                let entry = model.entryOrNew(for: $1.id)
                self.map($1, into: entry, index: $0)
                return entry
            }
        }
        model.parentId <=> viewModel.parentId
    }

    // MARK: - other mappers
    
    private func coupFumble(from model: String?) -> [DiceModel.CoupFumbleOption] {
        guard let model else { return [] }

        return model.components(separatedBy: ",").compactMap {
            let value = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            return DiceModel.CoupFumbleOption(rawValue: value)
        }
    }

    private func reroleOptions(from model: String?) -> [DiceModel.RerollOption] {
        guard let model else { return [] }

        return model.components(separatedBy: ",").compactMap {
            let comp = $0.split(separator: "/")
            guard comp.count == 3 else { return nil }
            let rerole = DiceModel.RerollOption(number: Int(comp[0]) ?? 0, value: Int(comp[1]) ?? 0, maxDiceValue: comp[2] == "1")
            if rerole.number > 0 {
                return rerole
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
