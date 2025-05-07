// @copyright André Trettin

import Testing

@testable import AndrenalinKit
import Foundation
internal import CoreGraphics

struct LinkHighLightLocationTests {

    @Test
    func twoLocations() async throws {
        let link = LinkReplaceModel(name: "1", module: .dice, linkNumber: 0, itemId: UUID(), entryId: nil, markDown: "1", command: nil, range: "1".startIndex..<"1".endIndex)
        let rect1 = CGRect(x: 103, y: 30, width: 28, height: 20.5)
        let rect2 = CGRect(x: 131, y: 28, width: 43, height: 24.2)
        let loc1 = LinkHighLightLocation(id: "1", link: link, locations: [LinkLocationCoordinate(id: UUID(), run: "", rect: rect1), LinkLocationCoordinate(id: UUID(), run: "", rect: rect2)])

        let buttonLocations = loc1.buttonLocations
        try #require(buttonLocations.count == 1)
        #expect(buttonLocations[0].rect == CGRect(x: 103, y: 28, width: 28+43, height: 24.2))
    }
}
