// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftData

@Model 
public final class CharacterEntryDataModel {
    public init(
        itemId: UUID = UUID(),
        entryId: UUID = UUID(),
        index: Int = 0,
        name: String = "",
        content: String = "",
        valueType: CharacterEntryDataModel.ValueType = CharacterEntryDataModel.ValueType.text,
        diceId: UUID? = nil,
        valueId: UUID? = nil,
        parent: CharacterDataModel? = nil
    ) {
        self.itemId = itemId
        self.entryId = entryId
        self.index = index
        self.name = name
        self.content = content
        
        self.valueType = valueType
        self.diceId = diceId
        self.valueId = valueId
    }
    
    public var itemId: UUID = UUID()
    @Attribute(.preserveValueOnDeletion)
    public var entryId: UUID = UUID()
    public var index: Int = 0
    
    public var name: String = ""
    public var content: String = ""
    
    var valueType: ValueType = ValueType.text
    var diceId: UUID? = nil
    var valueId: UUID? = nil
    
    //@CodableIgnored
    var parent: CharacterDataModel? = nil
    
    //@Generable(description: "The typ of the content.")
    public enum ValueType: Int, Equatable, Hashable, Codable, CaseIterable, Identifiable, Sendable {
        case text = 0
        case number = 1
        case decimal = 2
        case selection = 4

        public var id: Int {
            rawValue
        }

        var localizedTitle: LocalizedStringResource {
            switch self {
            case .text: "Text"
            case .number: "Number"
            case .decimal: "Decimal"
            case .selection: "Selection"
            }
        }

        var title: String {
            String(localized: localizedTitle).localizedString
        }

        var icon: String {
            switch self {
                case .text: "doc.text"
                case .number: "textformat.12"
                case .decimal: "number"
                case .selection: "checkmark.square"
            }
        }
    }
}

// MARK: - Codable

extension CharacterEntryDataModel {
    public struct Value: Equatable, Hashable, Codable, Sendable {
        public init(itemId: UUID = UUID(), entryId: UUID = UUID(), index: Int = 0, name: String = "", content: String = "", valueType: ValueType = ValueType.text, diceId: UUID? = nil, valueId: UUID? = nil) {
            self.itemId = itemId
            self.entryId = entryId
            self.index = index
            self.name = name
            self.content = content
            self.valueType = valueType
            self.diceId = diceId
            self.valueId = valueId
        }
        public var itemId: UUID = UUID()
        public var entryId: UUID = UUID()
        public var index: Int = 0
        public var name: String = ""
        public var content: String = ""
        public var valueType: ValueType = ValueType.text
        public var diceId: UUID? = nil
        public var valueId: UUID? = nil
    }
    
    convenience init(_ model: Value) {
        self.init(itemId: model.itemId, entryId: model.entryId, index: model.index, name: model.name, content: model.content, valueType: model.valueType, diceId: model.diceId, valueId: model.valueId)
    }
    
    var codableModel: Value {
        Value(
            itemId: itemId,
            entryId: entryId,
            index: index,
            name: name,
            content: content,
            valueType: valueType,
            diceId: diceId,
            valueId: valueId
        )
    }
    
    func replace(_ model: Value) {
        itemId = model.itemId
        entryId = model.entryId
        index = model.index
        name = model.name
        content = model.content
        valueType = model.valueType
        diceId = model.diceId
        valueId = model.valueId
    }
}

extension CharacterEntryDataModel: EntryPersistentModel {
    func duplicate(newItemId: UUID, newEntryId: UUID) -> CharacterEntryDataModel {
        CharacterEntryDataModel(
            itemId: newItemId,
            entryId: newEntryId,
            index: index,
            name: name,
            content: content,
            valueType: valueType,
            diceId: diceId,
            valueId: valueId,
            parent: nil
        )
    }

    public func duplicate(name: String, index: Int) -> CharacterEntryDataModel {
        CharacterEntryDataModel(
            itemId: itemId,
            entryId: UUID(),
            index: index,
            name: name,
            content: content,
            valueType: valueType,
            diceId: diceId,
            valueId: valueId,
            parent: parent
        )
    }
    
    @MainActor var links: [LinkDataModel.Value] {
        guard let modelContext else { return [] }
        let linkRegisterController = LinkRegisterController(container: modelContext.container)
        let nameLinks = linkRegisterController.linkDataModel(in: name).map { $0.codableModel }
        let contentLinks = linkRegisterController.linkDataModel(in: content).map { $0.codableModel }
        return nameLinks + contentLinks
    }
}

#if !os(tvOS)
// MARK: - Generable

import FoundationModels

extension CharacterEntryDataModel {
    @Generable
    public struct GenValue: Equatable, Hashable, Codable, Sendable {
        public init(name: String, content: String, valueType: CharacterEntryDataModel.ValueType, groupedValues: CharacterDataModel.GenValue?) {
            self.name = name
            self.content = content
            self.valueType = valueType
            if let groupedValues {
                self.groupedValues = [groupedValues]
            } else {
                self.groupedValues = []
            }
        }
        
        @Guide(description: "The name is the title of the value")
        public var name: String = ""
        @Guide(description: "The content is the value for the character")
        public var content: String = ""
        @Guide(description: "The value type of content")
        public var valueType: CharacterEntryDataModel.ValueType = .text
        
        @Guide(description: "A folder of values. The name and content of this value is then empty", .maximumCount(1))
        public var groupedValues: [CharacterDataModel.GenValue]
    }
}

#endif
