// @copyright André Trettin

import CoreRPG
import SwiftUI

public struct ValueEntryModel: Identifiable, Equatable, Hashable, Codable, @unchecked Sendable {
    public init(id: UUID, name: String, type: ValueEntryModel.ValueType, isGenerator: Bool = false, value: String, diceId: UUID? = nil, valueId: UUID? = nil, displayState: Int = 0) {
        self.id = id
        self.name = name
        self.type = type
        self.isGenerator = isGenerator
        self.value = value
        self.diceId = diceId
        self.valueId = valueId
        self.displayState = displayState
    }

    public init(id: UUID, name: CRDT<String>, type: CRDT<ValueEntryModel.ValueType>, isGenerator: CRDT<Bool>, value: CRDT<String>, diceId: CRDT<UUID?>, valueId: CRDT<UUID?>, displayState: Int = 0) {
        self.id = id
        _name = name
        _type = type
        _isGenerator = isGenerator
        _value = value
        _diceId = diceId
        _valueId = valueId
        self.displayState = displayState
    }

    public enum ValueType: Int, Equatable, Hashable, Codable, CaseIterable, Identifiable {
        case text = 0
        case number = 1
        case decimal = 2
        case selection = 4

        public var id: Int {
            rawValue
        }

        public var localizedTitle: LocalizedStringResource {
            switch self {
            case .text: "Text"
            case .number: "Number"
            case .decimal: "Decimal"
            case .selection: "Selection"
            }
        }

        public var title: String {
            String(localized: localizedTitle).localizedString
        }

        public var icon: String {
            switch self {
                case .text: "doc.text"
                case .number: "textformat.12"
                case .decimal: "number"
                case .selection: "checkmark.square"
            }
        }
    }

    public let id: UUID
    @CRDT public var name: String
    @CRDT public var type: ValueType
    @CRDT public var isGenerator: Bool
    @CRDT public var value: String
    @CRDT public var diceId: UUID?
    @CRDT public var valueId: UUID?

    public var displayState: Int = 0

    mutating func reset(isGenerator: Bool) {
        if self.isGenerator != isGenerator {
            self.isGenerator = isGenerator
        }
    }

    mutating func reset(valueType: ValueType) {
        if type != valueType {
            type = valueType
        }
    }

    var isGeneratorToggle: Bool {
        get { isGenerator }
        set { reset(isGenerator: newValue) }
    }

    var isSelectedToggle: Bool {
        get { valueSelected }
        set { toggleSelection() }
    }

    var valueTypeToggle: ValueType {
        get { type }
        set { reset(valueType: newValue) }
    }

    var canCalculate: Bool {
        type == .number || type == .decimal
    }

    var canGenerator: Bool {
        type != .selection
    }

    var canSelection: Bool {
        type == .selection
    }
}

extension ValueEntryModel {
    func nameText(otherValue: String) -> String {
        let bold = name.starts(with: "**") ? "" : "**"
        let first = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var firstBold = first
        if !first.isEmpty {
            firstBold = "\(bold)\(first)\(bold)"
        }
        return firstBold
    }

    func valueLinkText(otherValue: String, withoutName: Bool = false) -> String {
        let bold = name.starts(with: "**") ? "" : "**"
        var first: String
        if valueId != nil {
            first = name == "Group" ? "" : name
        } else {
            first = name
        }
        first = first.trimmingCharacters(in: .whitespacesAndNewlines)
        var firstBold = withoutName ? "" : first
        if !firstBold.isEmpty {
            firstBold = "\(bold)\(first)\(bold): "
        }
        return "\(firstBold)\(value)\(otherValue)"
    }
    
    var valueDecimal: Double {
        get { Double(valueCalculated) ?? 0.0 }
        set {
            if type == .number {
                valueNumber = Int(newValue)
            } else {
                setValue(from: "\(newValue)")
            }
        }
    }

    var valueNumber: Int {
        get { Int(valueCalculated) ?? 0 }
        set {
            setValue(from: "\(newValue)")
        }
    }

    mutating func setValue(from text: String) {
        let comp = value.split(separator: "|")
        var newValue = comp.isEmpty ? "0" : String(comp[0])
        if text != "0" {
            newValue.append("|\(text)")
        }
        value = newValue
    }

    var valueSelected: Bool {
        type == .selection && value == "I"
    }

    mutating func toggleSelection() {
        guard type == .selection else { return }
        if valueSelected {
            value = ""
        } else {
            value = "I"
        }
    }

    mutating func resetSelection() {
        guard type == .selection else { return }
        value = ""
    }

    var valueCalculated: String {
        guard type == .number || type == .decimal else { return "0" }
        let calcValues =  value.split(separator: "|")
        if calcValues.count == 2 {
            return String(calcValues[1])
        } else {
            return "0"
        }
    }

    @MainActor func calculate(on result: String) -> String {
        if let final = Calculator.calculate(result) {
            if type == .number {
                if !(final.isNaN || final.isInfinite || abs(final) >= Double(Int.max)) {
                    let valueTemp = Int(final)
                    return "\(valueTemp)"
                } else {
                    return "0 Error"
                }
            } else {
                return "\(final)"
            }
        }
        return "0 Error"
    }
}

extension ValueEntryModel: EntryDataAccessable, ItemDuplicatable {
    public var content: String {
        get { value }
        set { value = newValue }
    }
    public var childId: UUID { id }
    public static func newChild(id: UUID) -> Self {
        empty(id)
    }

    public static var empty: ValueEntryModel {
        empty(UUID())
    }

    public static func empty(_ id: UUID) -> ValueEntryModel {
        ValueEntryModel(id: id, name: "", type: .text, value: "")
    }

    public func duplicate() -> ValueEntryModel {
        ValueEntryModel(id: UUID(), name: name, type: type, isGenerator: isGenerator, value: value, diceId: diceId, valueId: valueId, displayState: displayState)
    }

    public func filter(with search: String) -> Bool {
        (search.isEmpty || name.localizedCaseInsensitiveContains(search) || value.localizedCaseInsensitiveContains(search))
    }
    
    public func linkContent() -> String { value }
}

extension ValueEntryModel: ItemLinkEditable {
    public var textLinkContent: String {
        entryText(otherValue: "")
    }

    public func entryText(otherValue: String) -> String {
        let bold = name.starts(with: "**") ? "" : "**"
        return "\(bold)\(name.trimmingCharacters(in: .whitespacesAndNewlines))\(bold): \(value)\(otherValue)"
    }
}

extension ValueEntryModel: ItemDiffComparable {
    public func merge(_ other: ValueEntryModel) -> ValueEntryModel {
        ValueEntryModel(
            id: id,
            name: $name.merged(other: other.$name),
            type: $type.merged(other: other.$type),
            isGenerator: $isGenerator.merged(other: other.$isGenerator),
            value: $value.merged(other: other.$value),
            diceId: $diceId.merged(other: other.$diceId),
            valueId: $valueId.merged(other: other.$valueId),
            displayState: other.displayState
        )
    }

    public func isSame(_ other: ValueEntryModel) -> Bool {
        name == other.name &&
        type == other.type &&
        isGenerator == other.isGenerator &&
        value == other.value &&
        diceId == other.diceId &&
        valueId == other.valueId
    }
}

extension ValueEntryModel: ItemReferencable {}
