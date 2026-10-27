// @copyright André Trettin

import CoreData
import CoreSpotlight
import Foundation
import Testing

@testable import CoreRPG

/// CODE_AUDIT_AppIntents2 §4.1: a tapped Core Spotlight result carries the managed object's URI.
@Suite("Spotlight activity route")
struct SpotlightActivityRouteTests {
    @Test("Only the Core Spotlight activity type is recognised")
    func recognisesActivityType() {
        #expect(SpotlightActivityRoute.isSpotlightActivity(NSUserActivity(activityType: CSSearchableItemActionType)))
        #expect(!SpotlightActivityRoute.isSpotlightActivity(NSUserActivity(activityType: UserActivity.bundleIdentifierType)))
    }

    @Test("The identifier is read from the activity's user info")
    func readsIdentifier() {
        let activity = NSUserActivity(activityType: CSSearchableItemActionType)
        activity.userInfo = [CSSearchableItemActivityIdentifier: "x-coredata://store/RPGMap/p1"]
        #expect(SpotlightActivityRoute.uniqueIdentifier(of: activity) == "x-coredata://store/RPGMap/p1")
    }

    @Test("An activity that is not a Spotlight tap resolves to nothing")
    func ignoresOtherActivities() async {
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        let activity = NSUserActivity(activityType: UserActivity.bundleIdentifierType)
        #expect(await SpotlightActivityRoute.resolve(activity, in: context) == nil)
    }

    @Test("A Spotlight tap on something that is not an object of the store resolves to nothing")
    func ignoresForeignIdentifiers() async {
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        let activity = NSUserActivity(activityType: CSSearchableItemActionType)
        activity.userInfo = [CSSearchableItemActivityIdentifier: UUID().uuidString]
        #expect(await SpotlightActivityRoute.resolve(activity, in: context) == nil)
    }
}
