// @copyright André Trettin

#if !os(tvOS)

import Foundation
import FoundationModels

@Generable(description: "The block can be of four category: Adventure, Map, Character or Table.")
struct BlockGenModel: Equatable {
    @Guide(description: "The name of this block.")
    var name: String
    @Guide(description: "More information about the of this block. Usually a short summary or high level description.")
    var information: String
    @Guide(description: "Tags to describe the content.")
    var tags: [String]
    
    @Guide(description: "The identified ")
    var blockCategory: BlockCategoryGenModel
    
    @Guide(description: "Each category has usually several smaller chunks.")
    var entries: [BlockEntryGenModel]
}

@Generable()
enum BlockCategoryGenModel: String, CaseIterable, Equatable {
    case adventure
    case map
    case character
    case table
}

@Generable(description: "THe entry of the block: Adventure it could be scenarios, Maps could be rooms, Character could be values, and Table could be rows.")
struct BlockEntryGenModel: Equatable {
    @Guide(description: "The title of this particular section.")
    var title: String
    var content: String
}

#endif
