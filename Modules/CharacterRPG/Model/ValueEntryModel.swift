// @copyright André Trettin

import CoreRPG
import SwiftUI

public struct ValueEntryModel: Identifiable, Equatable, Hashable, Codable, Sendable {
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

    public enum ValueType: Int, Equatable, Hashable, Codable, CaseIterable, Identifiable, Sendable {
        case text = 0
        case number = 1
        case decimal = 2
        case selection = 4

        public var id: Int {
            rawValue
        }

        public var localizedTitle: LocalizedStringResource {
            switch self {
            case .text: LocalizedStringResource("Text", bundle: .module)
            case .number: LocalizedStringResource("Number", bundle: .module)
            case .decimal: LocalizedStringResource("Decimal", bundle: .module)
            case .selection: LocalizedStringResource("Selection", bundle: .module)
            }
        }

        public var title: String {
            String(localized: localizedTitle)
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

    mutating func reset(valueType: ValueType) {
        if type != valueType {
            type = valueType
        }
    }

    /// A group entry (one that points to a sub-item with `valueId`) stands for that item and has no
    /// number of its own, whatever type it was converted from. Calculating its empty value
    /// would show "= 0 Error".
    var canCalculate: Bool {
        valueId == nil && (type == .number || type == .decimal)
    }
}

extension ValueEntryModel {
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
                setValue(from: Self.modifierText(newValue))
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
        let base = Self.baseText(of: value)
        var newValue = base.isEmpty ? "0" : base
        if text != "0" {
            newValue.append("|\(text)")
        }
        value = newValue
    }

    /// The part of a "base|modifier" value before the separator. A "|" inside a markdown link
    /// (`[name](url)`) or inside parentheses belongs to the base, so a link whose visible name
    /// contains one is not cut in half. See CODE_AUDIT_23 §5.15.
    nonisolated static func baseText(of value: String) -> String {
        topLevelComponents(of: value).first ?? value
    }

    /// `value` split at each "|" outside a link or parentheses. Empty parts are kept.
    nonisolated static func topLevelComponents(of value: String) -> [String] {
        var components: [String] = []
        var depth = 0
        var start = value.startIndex
        for index in value.indices {
            switch value[index] {
            case "[", "(":
                depth += 1
            case "]", ")":
                depth = max(0, depth - 1)
            case "|" where depth == 0:
                components.append(String(value[start..<index]))
                start = value.index(after: index)
            default:
                break
            }
        }
        components.append(String(value[start...]))
        return components
    }

    /// A modifier as stored text: fixed notation with an `en_US` decimal point, as the
    /// calculator reads it. `"\(Double)"` gives "1e-05" for a small number, which the
    /// calculator cannot parse. See CODE_AUDIT_23 §5.16.
    nonisolated static func modifierText(_ number: Double) -> String {
        number.formatted(
            .number
                .locale(Locale(identifier: "en_US"))
                .grouping(.never)
                .precision(.significantDigits(1 ... 17))
        )
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
        let calcValues = Self.topLevelComponents(of: value)
        if calcValues.count == 2, !calcValues[1].isEmpty {
            return calcValues[1]
        } else {
            return "0"
        }
    }

    @MainActor func calculate(on result: String) -> String {
        if let final = Calculator.calculate(result) {
            guard !(final.isNaN || final.isInfinite) else { return "0 Error" }
            if type == .number {
                guard abs(final) < Double(Int.max) else { return "0 Error" }
                let valueTemp = Int(final)
                return "\(valueTemp)"
            } else {
                return "\(final)"
            }
        }
        return "0 Error"
    }
    
    var editType: SheetModelEditType {
        guard valueId == nil else { return .none }
        return switch type {
        case .text: .text
        case .number: .number
        case .decimal: .decimal
        case .selection: .selection
        }
    }
}

extension ValueEntryModel.ValueType {
    /// Inverse of `ValueEntryModel.editType` above — kept next to it so a new
    /// `ValueType`/`SheetModelEditType` case is visible in both directions at
    /// once instead of drifting silently across files. See CODE_AUDIT_Character §5.7.
    /// `nil` for `.none`, which has no corresponding `ValueType`.
    init?(editType: SheetModelEditType) {
        switch editType {
        case .text: self = .text
        case .number: self = .number
        case .decimal: self = .decimal
        case .selection: self = .selection
        case .none: return nil
        }
    }
}

extension ValueEntryModel: EntryDataAccessible {
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
        (search.isEmpty || name.localizedStandardContains(search) || value.localizedStandardContains(search))
    }
    
    public func linkContent() -> String { value }
}

extension ValueEntryModel: nonisolated ItemDuplicatable {}

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


#if DEBUG
extension ValueEntryModel {
    /// Creates a test fixture with sensible defaults for testing.
    ///
    /// All parameters have default values, allowing you to specify only what matters for your test:
    /// ```swift
    /// let entry = ValueEntryModel.fixture(name: "Test Entry", type: .number)
    /// ```
    public static func fixture(
        id: UUID = UUID(),
        name: String = "Test Entry",
        type: ValueType = .decimal,
        isGenerator: Bool = false,
        value: String = "0",
        diceId: UUID? = nil,
        valueId: UUID? = nil,
        displayState: Int = 0
    ) -> ValueEntryModel {
        ValueEntryModel(
            id: id,
            name: name,
            type: type,
            isGenerator: isGenerator,
            value: value,
            diceId: diceId,
            valueId: valueId,
            displayState: displayState
        )
    }
}
#endif

/// The entry's group link for the shared group functions. See CODE_AUDIT_Folder §9.9.
extension ValueEntryModel: GroupableEntry {
    public var groupItemId: UUID? {
        get { valueId }
        set { valueId = newValue }
    }
}
