// @copyright André Trettin

import CodableModel
import Foundation
import SwiftData

@Model @CodableModel
public final class CharacterEntryDataModel {
    public init(itemId: UUID = UUID(), entryId: UUID = UUID(), index: Int = 0, name: String = "", content: String = "", valueType: CharacterEntryDataModel.ValueType = CharacterEntryDataModel.ValueType.text, diceId: UUID? = nil, valueId: UUID? = nil, parent: CharacterDataModel? = nil) {
        self.itemId = itemId
        self.entryId = entryId
        self.index = index
        self.name = name
        self.content = content
        self.valueType = valueType
        self.diceId = diceId
        self.valueId = valueId
    }
    
    var itemId: UUID = UUID()
    var entryId: UUID = UUID()
    var index: Int = 0
    
    var name: String = ""
    var content: String = ""
    var valueType: ValueType = ValueType.text
    
    var diceId: UUID? = nil
    var valueId: UUID? = nil
    
    @CodableIgnored
    var parent: CharacterDataModel? = nil
    
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
