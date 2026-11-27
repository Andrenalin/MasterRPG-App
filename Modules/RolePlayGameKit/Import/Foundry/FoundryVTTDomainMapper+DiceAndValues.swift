// @copyright André Trettin

import AdventureRPG
import AudioRPG
import CharacterRPG
import CoreRPG
import DiceRPG
import Foundation
import MapRPG
import Observation
import PdfRPG
import PhotoRPG
import RuleRPG
import SpaceRPG
import SwiftUI
import TableRPG
import UniformTypeIdentifiers

// MARK: - Dice and values

extension FoundryMappingState {
    func createDice(formula: String, name: String, sourceId: String) -> UUID? {
        let range = NSRange(formula.startIndex..<formula.endIndex, in: formula)
        // MasterRPG can represent additive dice plus a numeric modifier. Foundry roll syntax also
        // supports pools, keep/drop, functions, variables, comparisons, and multiplication. Never
        // project a matching substring from those richer expressions as if it were equivalent.
        let supportedGrammar = FoundryMapperPatterns.supportedFormula
        guard supportedGrammar?.firstMatch(in: formula, range: range)?.range == range else {
            warnings.append(String(localized: "Roll formula ‘\(formula)’ uses Foundry syntax that is not exactly representable; it remains text in the raw archive.", bundle: .module))
            return nil
        }

        let pattern = FoundryMapperPatterns.dieMatch
        let matches = pattern?.matches(in: formula, range: range) ?? []
        var dice: [DieModel] = []
        for match in matches {
            guard let sidesRange = Range(match.range(at: 2), in: formula),
                  let sides = Int(formula[sidesRange]), sides > 0 else {
                warnings.append(String(localized: "Roll formula ‘\(formula)’ contains an invalid die and remains text in the raw archive.", bundle: .module))
                return nil
            }
            let count: Int
            if let countRange = Range(match.range(at: 1), in: formula), !countRange.isEmpty {
                guard let parsedCount = Int(formula[countRange]), (1...100).contains(parsedCount) else {
                    warnings.append(String(localized: "Roll formula ‘\(formula)’ exceeds the supported limit of 100 dice and remains text in the raw archive.", bundle: .module))
                    return nil
                }
                count = parsedCount
            } else {
                count = 1
            }
            // The total per formula is capped too, not only each term (`100d6 + 100d6 + ...`).
            // See CODE_AUDIT_26 §5.126.
            guard dice.count + count <= 100 else {
                warnings.append(String(localized: "Roll formula ‘\(formula)’ exceeds the supported limit of 100 dice and remains text in the raw archive.", bundle: .module))
                return nil
            }
            for index in 0..<count {
                dice.append(DieModel(
                    id: stableId("\(sourceId)#die#\(match.range.location)#\(index)"),
                    die: RawDie(text: "d\(sides)")
                ))
            }
        }
        guard !dice.isEmpty else {
            warnings.append(String(localized: "Roll formula ‘\(formula)’ is preserved as text because it has no directly representable dice.", bundle: .module))
            return nil
        }
        let modifier = simpleModifier(formula)
        guard modifier.isFinite else {
            warnings.append(String(localized: "Roll formula ‘\(formula)’ has a modifier outside the supported numeric range and remains text in the raw archive.", bundle: .module))
            return nil
        }
        let id = stableId("\(sourceId)#dice")
        let model = DiceModel(
            id: id,
            name: "\(name) (\(formula))",
            description: "Original Foundry formula: \(formula)",
            tags: ["Foundry VTT"],
            category: .rules,
            dice: dice,
            modifier: modifier
        )
        add(model, module: .dice, sourceId: "\(sourceId)#formula")
        return id
    }

    func hierarchicalEntries(
        _ value: FoundryJSONValue?,
        sourceId: String,
        ownerId: UUID,
        decisionOwnerId: UUID
    ) -> [ValueEntryModel] {
        guard let value else { return [] }
        // Planned off the main actor when the pre-pass saw this value. See CODE_AUDIT_29 §3.4.
        let nodes: [FoundryValuePlanNode]
        if let plan = valuePlans[sourceId], plan.value == value {
            nodes = plan.nodes
        } else {
            nodes = FoundryValuePrepass.plan(value, sourceId: sourceId, scope: sourceScopeId)
        }
        let valueCount = nodes.reduce(0) { $0 + $1.valueCount }
        let maximumPresentedValues = 500
        if valueCount > maximumPresentedValues {
            warnings.append(String(localized: "\(sourceId) has \(valueCount) system fields; the display projection includes the first \(maximumPresentedValues) and the archive retains all fields.", bundle: .module))
        }
        var remainingValues = maximumPresentedValues
        return projectedValueEntries(
            nodes,
            sourceId: sourceId,
            ownerId: ownerId,
            decisionOwnerId: decisionOwnerId,
            remainingValues: &remainingValues
        )
    }

    func projectedValueEntries(
        _ nodes: [FoundryValuePlanNode],
        sourceId: String,
        ownerId: UUID,
        decisionOwnerId: UUID,
        remainingValues: inout Int
    ) -> [ValueEntryModel] {
        var entries: [ValueEntryModel] = []
        for node in nodes {
            guard remainingValues > 0 else { break }
            guard let groupIds = node.groupIds else {
                guard let value = node.value else { continue }
                remainingValues -= 1
                let presentation = valuePresentation(value)
                entries.append(ValueEntryModel(
                    id: node.fieldId,
                    name: node.name,
                    type: presentation.type,
                    value: presentation.value
                ))
                continue
            }

            var childEntries: [ValueEntryModel] = []
            if let value = node.value, remainingValues > 0 {
                remainingValues -= 1
                let presentation = valuePresentation(value)
                childEntries.append(ValueEntryModel(
                    id: groupIds.value,
                    name: "value",
                    type: presentation.type,
                    value: presentation.value
                ))
            }
            childEntries.append(contentsOf: projectedValueEntries(
                node.children,
                sourceId: sourceId,
                ownerId: groupIds.group,
                decisionOwnerId: decisionOwnerId,
                remainingValues: &remainingValues
            ))
            guard !childEntries.isEmpty else { continue }

            let groupModel = ValueModel(
                id: groupIds.group,
                name: node.name,
                category: .item,
                displayState: DisplayStateMask.groupHidden.rawValue,
                entries: childEntries,
                groupId: ownerId
            )
            add(
                groupModel,
                module: .value,
                sourceId: sourceId,
                decisionOwnerId: decisionOwnerId
            )
            entries.append(ValueEntryModel(
                id: groupIds.link,
                name: node.name,
                type: .text,
                value: "",
                valueId: groupIds.group
            ))
        }
        return entries
    }

    func valuePresentation(_ value: FoundryJSONValue) -> (type: ValueEntryModel.ValueType, value: String) {
        switch value {
        case .integer(let value): (.number, String(value))
        case .unsignedInteger(let value): (.number, String(value))
        case .number(let value): (.decimal, String(value))
        case .bool(let value): (.selection, value ? "I" : "")
        case .string(let value): (.text, decodedFoundryText(value))
        case .array, .object: (.text, displayString(value))
        case .null: (.text, "")
        }
    }
}
