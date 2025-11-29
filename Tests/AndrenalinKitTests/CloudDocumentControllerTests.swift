// @copyright André Trettin

import Foundation
import Testing

@testable import CoreRPG

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

    @Test(arguments: [
        ("test.second.jpg", "test.second-1.jpg"),
        ("test.more.and.more-1.jpg", "test.more.and.more-2.jpg"),
        ("test_2.crazy....jpg", "test_2.crazy...-1.jpg"),
    ])
    func nameWithMultipleExtension(what: (input: String, output: String)) async throws {
        #expect(what.output == CloudDocumentController.increasedFileName(for: what.input))
    }

    @Test(arguments: [
        ("test-1-1.jpg", "test-1-2.jpg"),
        ("test-2_1-1.jpg", "test-2_1-2.jpg"),
        ("test-----.jpg", "test------1.jpg"),
    ])
    func nameWithMultipleCounters(what: (input: String, output: String)) async throws {
        #expect(what.output == CloudDocumentController.increasedFileName(for: what.input))
    }

    @Test(arguments: [
        ("test-1-A.jpg", "test-1-A-1.jpg"),
        ("test-2_1-B.jpg", "test-2_1-B-1.jpg"),
        ("test-A-B-C-.jpg", "test-A-B-C--1.jpg"),
    ])
    func nameWithInvailCounters(what: (input: String, output: String)) async throws {
        #expect(what.output == CloudDocumentController.increasedFileName(for: what.input))
    }
}
