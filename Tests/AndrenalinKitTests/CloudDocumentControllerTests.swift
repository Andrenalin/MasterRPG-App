// @copyright André Trettin

import Foundation
import Testing

@testable import AndrenalinKit

struct CloudDocumentControllerTests {
    @Test(arguments: [
        ("test", "test-1"),
        ("test-1", "test-2"),
        ("test_2", "test_2-1"),
    ])
    func onlyName(what: (input: String, output: String)) async throws {
        #expect(what.output == CloudDocumentController.increasedFileName(for: what.input))
    }

    @Test(arguments: [
        ("test.jpg", "test-1.jpg"),
        ("test-1.jpg", "test-2.jpg"),
        ("test_2.jpg", "test_2-1.jpg"),
    ])
    func nameWithExtension(what: (input: String, output: String)) async throws {
        #expect(what.output == CloudDocumentController.increasedFileName(for: what.input))
    }
}
