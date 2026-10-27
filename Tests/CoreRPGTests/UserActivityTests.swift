// @copyright André Trettin

import Foundation
import Testing

@testable import CoreRPG

/// CODE_AUDIT §5.2: every module that posts a detail activity must resolve back to its module,
/// or Handoff and `RPG://` links for it open nothing.
@Suite("User activity module tokens")
struct UserActivityTests {
    /// The modules with a library detail screen that posts `UserActivity.addPayLoad`.
    private static let detailModules: [NetworkModules] = [
        .adventure, .audio, .dice, .generator, .map, .pdf, .photo, .rule, .space, .table, .value, .weather
    ]

    @Test("The token of every detail module resolves back to it", arguments: detailModules)
    func tokenRoundTrips(module: NetworkModules) {
        #expect(UserActivity.extractModule(from: module.token) == module)
    }

    @Test("A deep link to a generator item names the generator module")
    func generatorLinkResolves() throws {
        let url = try #require(URL(string: "RPG://GENERATOR/0/00000000-0000-0000-0000-000000000001"))
        #expect(url.moduleIdentifier == .generator)
    }

    @Test("The payload round-trips module and item for a generator item")
    func payloadRoundTrips() {
        let activity = NSUserActivity(activityType: UserActivity.bundleIdentifierType)
        let itemId = UUID()
        UserActivity.addPayLoad(for: activity, title: "Generator", module: .generator, itemId: itemId)

        #expect(UserActivity.module(from: activity) == .generator)
        #expect(UserActivity.itemId(from: activity) == itemId)
    }
}
