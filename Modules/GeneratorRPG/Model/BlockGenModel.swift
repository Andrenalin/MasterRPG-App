// @copyright André Trettin

#if !os(tvOS)

import Foundation
import FoundationModels

@Generable(description: "The block can be of four category: Adventure, Map, Character or Table.")
public struct BlockGenModel: Equatable, Identifiable, Sendable {
    public let id: UUID = UUID()
    @Guide(description: "The name of this block.")
    public let name: String
    @Guide(description: "More information about the of this block. Usually a short summary or high level description.")
    public let information: String
    @Guide(description: "Tags to describe the content.")
    public let tags: [String]

    @Guide(description: "The block is from Type Adventure, Map, Character or Table.")
    public let blockCategory: BlockCategoryGenModel

    @Guide(description: "Each category has usually several smaller chunks.")
    public var entries: [BlockEntryGenModel]
}

@Generable()
public enum BlockCategoryGenModel: String, CaseIterable, Equatable, Sendable {
    case adventure
    case map
    case character
    case table
}

@Generable(description: "THe entry of the block: Adventure it could be scenarios, Maps could be rooms, Character could be values, and Table could be rows.")
public struct BlockEntryGenModel: Equatable, Identifiable, Sendable {
    public let id: UUID = UUID()
    @Guide(description: "A short title of this particular section.")
    public let title: String
    public let content: String
}

#endif
