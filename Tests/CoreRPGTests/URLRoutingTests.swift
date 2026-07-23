// @copyright André Trettin

#if canImport(Testing)
import Foundation
import Testing

@testable import CoreRPG

struct URLRoutingTests {
    @Test func gmzExtensionIsCaseInsensitive() throws {
        let url = try #require(URL(string: "file:///tmp/Adventure.GMZ"))

        #expect(url.isGmzDocument)
    }

    @Test func appSchemeAndModuleHostAreCaseInsensitive() throws {
        let url = try #require(URL(string: "RPG://VALUES/1/00000000-0000-0000-0000-000000000001"))

        #expect(url.isDeeplink)
        #expect(url.moduleIdentifier == .value)
        #expect(url.itemId == UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
    }
}
#endif
