// @copyright André Trettin

import Foundation
import Testing

@testable import CoreRPG

/// Test case for filename increment behavior.
///
/// Provides descriptive names for test output to identify which scenario failed.
struct FileNameIncrementTestCase: CustomStringConvertible {
    let input: String
    let expected: String

    var description: String {
        "increment '\(input)' → '\(expected)'"
    }
}

struct CloudDocumentControllerTests {
    @Test(arguments: [
        FileNameIncrementTestCase(input: "test", expected: "test-1"),
        FileNameIncrementTestCase(input: "test-1", expected: "test-2"),
        FileNameIncrementTestCase(input: "test_2", expected: "test_2-1"),
    ])
    func onlyName(testCase: FileNameIncrementTestCase) async throws {
        #expect(testCase.expected == CloudDocumentController.increasedFileName(for: testCase.input))
    }

    @Test(arguments: [
        FileNameIncrementTestCase(input: "test.jpg", expected: "test-1.jpg"),
        FileNameIncrementTestCase(input: "test-1.jpg", expected: "test-2.jpg"),
        FileNameIncrementTestCase(input: "test_2.jpg", expected: "test_2-1.jpg"),
    ])
    func nameWithExtension(testCase: FileNameIncrementTestCase) async throws {
        #expect(testCase.expected == CloudDocumentController.increasedFileName(for: testCase.input))
    }

    @Test(arguments: [
        FileNameIncrementTestCase(input: "test.second.jpg", expected: "test.second-1.jpg"),
        FileNameIncrementTestCase(input: "test.more.and.more-1.jpg", expected: "test.more.and.more-2.jpg"),
        FileNameIncrementTestCase(input: "test_2.crazy....jpg", expected: "test_2.crazy...-1.jpg"),
    ])
    func nameWithMultipleExtension(testCase: FileNameIncrementTestCase) async throws {
        #expect(testCase.expected == CloudDocumentController.increasedFileName(for: testCase.input))
    }

    @Test(arguments: [
        FileNameIncrementTestCase(input: "test-1-1.jpg", expected: "test-1-2.jpg"),
        FileNameIncrementTestCase(input: "test-2_1-1.jpg", expected: "test-2_1-2.jpg"),
        FileNameIncrementTestCase(input: "test-----.jpg", expected: "test------1.jpg"),
    ])
    func nameWithMultipleCounters(testCase: FileNameIncrementTestCase) async throws {
        #expect(testCase.expected == CloudDocumentController.increasedFileName(for: testCase.input))
    }

    @Test(arguments: [
        FileNameIncrementTestCase(input: "test-1-A.jpg", expected: "test-1-A-1.jpg"),
        FileNameIncrementTestCase(input: "test-2_1-B.jpg", expected: "test-2_1-B-1.jpg"),
        FileNameIncrementTestCase(input: "test-A-B-C-.jpg", expected: "test-A-B-C--1.jpg"),
    ])
    func nameWithInvailCounters(testCase: FileNameIncrementTestCase) async throws {
        #expect(testCase.expected == CloudDocumentController.increasedFileName(for: testCase.input))
    }
}
