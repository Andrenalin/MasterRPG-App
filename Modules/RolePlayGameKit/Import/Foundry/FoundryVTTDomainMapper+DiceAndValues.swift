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
    func createDice(formula: String, name: String, sourceID: String) -> UUID? {
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
            for index in 0..<count {
                dice.append(DieModel(
                    id: stableID("\(sourceID)#die#\(match.range.location)#\(index)"),
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
        let id = stableID("\(sourceID)#dice")
        let model = DiceModel(
            id: id,
            name: "\(name) (\(formula))",
            description: "Original Foundry formula: \(formula)",
            tags: ["Foundry VTT"],
            category: .rules,
            dice: dice,
            modifier: modifier
        )
        add(model, module: .dice, sourceID: "\(sourceID)#formula")
        return id
    }

    func hierarchicalEntries(
        _ value: FoundryJSONValue?,
        sourceID: String,
        ownerID: UUID,
        decisionOwnerID: UUID
    ) -> [ValueEntryModel] {
        guard let value else { return [] }
        let nodes = FoundryValueHierarchy.nodes(from: value)
        let valueCount = nodes.reduce(0) { $0 + $1.valueCount }
        let maximumPresentedValues = 500
        if valueCount > maximumPresentedValues {
            warnings.append(String(localized: "\(sourceID) has \(valueCount) system fields; the display projection includes the first \(maximumPresentedValues) and the archive retains all fields.", bundle: .module))
        }
        var remainingValues = maximumPresentedValues
        return projectedValueEntries(
            nodes,
            sourceID: sourceID,
            ownerID: ownerID,
            decisionOwnerID: decisionOwnerID,
            remainingValues: &remainingValues
        )
    }

    func projectedValueEntries(
        _ nodes: [FoundryValueNode],
        sourceID: String,
        ownerID: UUID,
        decisionOwnerID: UUID,
        remainingValues: inout Int
    ) -> [ValueEntryModel] {
        var entries: [ValueEntryModel] = []
        for node in nodes {
            guard remainingValues > 0 else { break }
            let pathIdentity = valuePathIdentity(node.pathComponents)
            if node.children.isEmpty, let value = node.value {
                remainingValues -= 1
                let presentation = valuePresentation(value)
                entries.append(ValueEntryModel(
                    id: stableID("\(sourceID)#field#\(pathIdentity)"),
                    name: FoundryTextDecoder.decodedText(node.component),
                    type: presentation.type,
                    value: presentation.value
                ))
                continue
            }

            let groupID = stableID("\(sourceID)#field-group#\(pathIdentity)")
            var childEntries: [ValueEntryModel] = []
            if let value = node.value, remainingValues > 0 {
                remainingValues -= 1
                let presentation = valuePresentation(value)
                childEntries.append(ValueEntryModel(
                    id: stableID("\(sourceID)#field#\(pathIdentity)#value"),
                    name: "value",
                    type: presentation.type,
                    value: presentation.value
                ))
            }
            childEntries.append(contentsOf: projectedValueEntries(
                node.children,
                sourceID: sourceID,
                ownerID: groupID,
                decisionOwnerID: decisionOwnerID,
                remainingValues: &remainingValues
            ))
            guard !childEntries.isEmpty else { continue }

            let groupName = FoundryTextDecoder.decodedText(node.component)
            let groupModel = ValueModel(
                id: groupID,
                name: groupName,
                category: .item,
                displayState: DisplayStateMask.groupHidden.rawValue,
                entries: childEntries,
                groupId: ownerID
            )
            add(
                groupModel,
                module: .value,
                sourceID: sourceID,
                decisionOwnerID: decisionOwnerID
            )
            entries.append(ValueEntryModel(
                id: stableID("\(sourceID)#field-group-link#\(pathIdentity)"),
                name: groupName,
                type: .text,
                value: "",
                valueId: groupID
            ))
        }
        return entries
    }

    func valuePathIdentity(_ components: [String]) -> String {
        guard !components.isEmpty else { return "root" }
        return components.map { component in
            "\(component.utf8.count):\(component)"
        }.joined()
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
