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

    /// CODE_AUDIT_21 §6.4: `Int.max + 1` trapped.
    @Test(arguments: [
        FileNameIncrementTestCase(input: "a-9223372036854775807.jpg", expected: "a-9223372036854775807-1.jpg"),
        FileNameIncrementTestCase(input: "a-9223372036854775807", expected: "a-9223372036854775807-1"),
        FileNameIncrementTestCase(input: "a-9223372036854775806.jpg", expected: "a-9223372036854775807.jpg"),
    ])
    func counterAtIntMaxDoesNotOverflow(testCase: FileNameIncrementTestCase) async throws {
        #expect(testCase.expected == CloudDocumentController.increasedFileName(for: testCase.input))
    }
}

/// A device keeps its containers below `/private/var`. `standardizedFileURL` drops `/private`
/// only from a path that exists, so a file still to be written compared as outside its existing
/// module folder: a player could not store a photo or map the game master sent, and no new file
/// could be added. A simulator's containers are below `/Users`, so the folder is made below
/// `/private/tmp` here.
@Suite(.enabled(if: PrivateRootFolder.isAvailable))
struct CloudDocumentControllerPrivateRootTests {
    @Test("A file that is not written yet lies inside its existing folder")
    func newFileIsContainedInExistingFolder() throws {
        let folder = try PrivateRootFolder()
        defer { folder.remove() }
        let newFile = folder.url.appending(path: "Sub Folder").appending(path: "new #1.jpg")

        #expect(CloudDocumentController.isContained(newFile, in: folder.url))
        #expect(CloudDocumentController.isContained(folder.url, in: folder.url))
        #expect(!CloudDocumentController.isContained(folder.url.appending(path: "../other/x.jpg"), in: folder.url))
        #expect(!CloudDocumentController.isContained(folder.url.deletingLastPathComponent(), in: folder.url))
    }

    @Test("The canonical path of a file does not depend on whether the file exists")
    func canonicalPathIsIndependentOfExistence() throws {
        let folder = try PrivateRootFolder()
        defer { folder.remove() }
        let file = folder.url.appending(path: "photo.jpg")
        let folderPath = CloudDocumentController.canonicalPath(folder.url)

        let pathBeforeWriting = CloudDocumentController.canonicalPath(file)
        #expect(pathBeforeWriting == folderPath + "/photo.jpg")

        try Data([1]).write(to: file)
        #expect(CloudDocumentController.canonicalPath(file) == pathBeforeWriting)

        // The same file, spelled without the `/private` prefix.
        let shortSpelling = URL(filePath: file.path(percentEncoded: false).replacing("/private/tmp/", with: "/tmp/"))
        #expect(CloudDocumentController.canonicalPath(shortSpelling) == pathBeforeWriting)
    }

    @Test("A folder that does not exist yet contains its files as well")
    func missingFolderContainsItsFiles() throws {
        let folder = try PrivateRootFolder()
        defer { folder.remove() }
        let missingFolder = folder.url.appending(path: "pdf")
        let file = missingFolder.appending(path: "Rules.pdf")

        #expect(CloudDocumentController.isContained(file, in: missingFolder))
        #expect(CloudDocumentController.canonicalPath(file) == CloudDocumentController.canonicalPath(missingFolder) + "/Rules.pdf")
    }
}

/// An existing folder below `/private/tmp`, the spelling a device's container urls have.
private struct PrivateRootFolder {
    private static let root = URL(filePath: "/private/tmp", directoryHint: .isDirectory)

    static var isAvailable: Bool {
        FileManager.default.isWritableFile(atPath: root.path(percentEncoded: false))
    }

    let url: URL

    init() throws {
        url = Self.root.appending(path: "CloudDocumentControllerTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}
