// @copyright André Trettin

import Foundation
import Testing

@testable import CoreRPG

/// Each `*Entity.urlRepresentation` hardcodes `RPG://<TOKEN>/0/<id>` (the template cannot take a
/// runtime string, see `DiceEntity`). This pins the literals to `NetworkModules.token` and shows the
/// app's URL parser resolves them. See CODE_AUDIT_AppIntents2 §4.1.
@Suite("Entity URL representations")
struct EntityUrlRepresentationTests {
    /// The module and the token literal written in its entity's `urlRepresentation`.
    private static let literals: [(module: NetworkModules, token: String)] = [
        (.adventure, "ADVENTURES"), (.audio, "AUDIOS"), (.dice, "DICE"), (.generator, "GENERATOR"),
        (.map, "MAPS"), (.pdf, "PDFS"), (.photo, "PHOTOS"), (.rule, "RULES"), (.space, "SPACES"),
        (.table, "TABLES"), (.value, "VALUES"), (.weather, "WEATHERS")
    ]

    @Test("The scheme is the one the entities spell out")
    func scheme() {
        #expect(URL.appScheme == "RPG")
    }

    @Test("The literal token equals the module's token and its link resolves", arguments: literals)
    func literalResolves(module: NetworkModules, token: String) throws {
        #expect(module.token == token)
        let itemId = UUID()
        let url = try #require(URL(string: "RPG://\(token)/0/\(itemId.uuidString)"))
        #expect(url.moduleIdentifier == module)
        #expect(url.itemId == itemId)
    }
}
