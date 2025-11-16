#if !os(tvOS)
// MARK: - Generable

import Foundation
import FoundationModels

@Generable(description: "The character description")
public struct CharacterGenModel: Equatable, Hashable, Codable, Sendable {
    public init(name: String, information: String, tags: [String], entries: [CharacterEntryGenModel] = []) {
        self.name = name
        self.information = information
        self.tags = tags
        self.entries = entries
    }
    
    @Guide(description: "The name of the character or the group of values")
    public var name: String
    @Guide(description: "A description about the character ot the group")
    public var information: String
    @Guide(description: "A tag description", .maximumCount(5))
    public var tags: [String]
    @Guide(description: "A character has many named values like key value pairs")
    public var entries: [CharacterEntryGenModel] = []
}

@Generable
public struct CharacterEntryGenModel: Equatable, Hashable, Codable, Sendable {
    public init(name: String, content: String, valueType: CharacterEntryGenModel.ValueType, groupedValues: CharacterGenModel?) {
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
    public var valueType: CharacterEntryGenModel.ValueType = .text
    
    @Guide(description: "A folder of values. The name and content of this value is then empty", .maximumCount(1))
    public var groupedValues: [CharacterGenModel]
    
    
    @Generable(description: "The typ of the content.")
    public enum ValueType: Int, Equatable, Hashable, Codable, CaseIterable, Identifiable, Sendable {
        case text = 0
        case number = 1
        case decimal = 2
        case selection = 4
        
        public var id: Int {
            rawValue
        }
    }
}


#endif
