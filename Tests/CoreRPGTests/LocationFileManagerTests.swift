// @copyright André Trettin

import Foundation
import Testing

@testable import CoreRPG

struct LocationFileManagerTests {
    @Test func folders() async throws {
        let sut = LocationFileManager(moduleFolder: "TestsFolders")
        #expect(sut.moduleFolder == "TestsFolders")
        #expect(nil != sut.rootLocal)
        #expect(sut.rootLocal == URL.documentsDirectory)

        // Always nil in Test target, because the test target is not configure to have iCloud
        #expect(nil == sut.rootAppCloud)
        #expect(nil == sut.rootICloud)
    }

    @Test func fileLocation() async throws {
        let sut = LocationFileManager(moduleFolder: "TestsFileLocation")
        let docUrl = URL.documentsDirectory
        let docFileUrl = URL.documentsDirectory.appending(path: "test.txt")
        let downloadUrl = URL.downloadsDirectory

        #expect(sut.fileLocation(for: docUrl) == CoreRPG.FileLocation.local)
        #expect(sut.fileLocation(for: docFileUrl) == CoreRPG.FileLocation.local)
        #expect(sut.fileLocation(for: downloadUrl) == CoreRPG.FileLocation.newCloud)
    }

    @Test func absoluteUrl() async throws {
        let sut = LocationFileManager(moduleFolder: "TestsAbsolutUrl")
        let docFileUrl = URL.documentsDirectory.appending(path: "test.txt")
        // these are nil because the icloud is not active
        #expect(nil == sut.absoluteUrl(for: docFileUrl, at: .appCloud))
        #expect(nil == sut.absoluteUrl(for: docFileUrl, at: .icloud))
        #expect(sut.absoluteUrl(for: docFileUrl, at: .local) == docFileUrl)
        #expect(sut.absoluteUrl(for: docFileUrl, at: .other) == docFileUrl)
    }

    @Test func relativeUrlKeepsLocalPaths() async throws {
        let sut = LocationFileManager(moduleFolder: "TestsRelativeUrl")
        let docFileUrl = URL.documentsDirectory.appending(path: "test.txt")

        #expect(sut.relativeUrl(for: docFileUrl) == docFileUrl)
    }
}
