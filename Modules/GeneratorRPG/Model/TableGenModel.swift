// @copyright André Trettin

import Foundation
import FoundationModels

@Generable(description: "A table can be a list of only the content, or it is a key value pair. The key is the name and the content is the value.")
struct TableGenModel {
    @Guide(description: "The name of the table.")
    var name: String
    @Guide(description: "More information about the table and the contents.")
    var information: String
    @Guide(description: "Tags to describe the table contents.")
    var tags: [String]
    
    @Guide(description: "Some table you roll some dice to get some random content. This is used for loot tables, encounter or other random events.")
    var diceValue: String?
    
    @Guide(description: "The content of the table. Each entry represents one row.")
    var entries: [TableEntryGenModel]
}


@Generable(description: "The content row of the tbale.")
struct TableEntryGenModel {
    @Guide(description: "The name of the row. In a dice table thius contains the number range of the dice.")
    var name: String
    @Guide(description: "The content of the table row.")
    var content: String

    @Guide(description: "A link to another table. The link is inside the content and the name is used to identify it.", .minimumCount(0))
    var links: [TableLinkGenModel]
}

@Generable(description: "A link to another table. It is not often that content links to another table.")
struct TableLinkGenModel {
    @Guide(description: "The name of the linked table.")
    var name: String
}
