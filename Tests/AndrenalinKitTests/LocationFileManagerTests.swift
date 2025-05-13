// @copyright André Trettin

import Foundation
import Testing

@testable import AndrenalinKit

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

    @Test func FileLocation() async throws {
        let sut = LocationFileManager(moduleFolder: "TestsFileLocation")
        let docUrl = URL.documentsDirectory
        let docFileUrl = URL.documentsDirectory.appendingPathComponent("test.txt")
        let downloadUrl = URL.downloadsDirectory

        #expect(sut.fileLocation(for: docUrl) == AndrenalinKit.FileLocation.local)
        #expect(sut.fileLocation(for: docFileUrl) == AndrenalinKit.FileLocation.local)
        #expect(sut.fileLocation(for: downloadUrl) == AndrenalinKit.FileLocation.newCloud)
    }

    @Test func AbsolutUrl() async throws {
        let sut = LocationFileManager(moduleFolder: "TestsAbsolutUrl")
        let docFileUrl = URL.documentsDirectory.appendingPathComponent("test.txt")
        // these are nil because the icloud is not active
        #expect(nil == sut.absoluteUrl(for: docFileUrl, at: .appCloud))
        #expect(nil == sut.absoluteUrl(for: docFileUrl, at: .icloud))
        #expect(sut.absoluteUrl(for: docFileUrl, at: .local) == docFileUrl)
        #expect(sut.absoluteUrl(for: docFileUrl, at: .other) == docFileUrl)
    }

    @Test func remove() async throws {
        let sut = LocationFileManager(moduleFolder: "TestsRemove")
        let docFileUrl = URL.temporaryDirectory.appendingPathComponent("test.txt")
        try await #require(performing: {
            try await sut.remove(url: docFileUrl)
        }, throws: { error in
            true
        })
    }

    @Test func create() async throws {
        let sut = LocationFileManager(moduleFolder: "TestsCreate")
        let id = UUID()
        let url = try await sut.create(id: id, location: .local, pathExtension: "txt", data: Data(count: 4))
        #expect(nil != url)
        #expect(sut.fileLocation(for: url) == .local)
        #expect(try Data(contentsOf: url!).count == 4)
        try await sut.remove(url: url!)
        try await sut.remove(url: URL.documentsDirectory.appending(path: "TestsCreate"))
    }

    @Test func copy() async throws {
        let sut = LocationFileManager(moduleFolder: "TestsCopy")
        let id = UUID()
        let url = try await sut.create(id: id, location: .local, pathExtension: "txt", data: Data(count: 4))
        let newUrl = try await sut.copy(pickedURL: url!, to: URL.temporaryDirectory.appending(path: id.uuidString).appendingPathExtension("txt"))
        #expect(nil != newUrl)
        #expect(sut.fileLocation(for: newUrl!) == .newCloud)
        #expect(try Data(contentsOf: newUrl!).count == 4)
        #expect(!FileManager.default.fileExists(atPath: url!.absoluteString))

        let oldUrl = try await sut.copy(pickedURL: newUrl!, to: .local, id: id)
        #expect(nil != oldUrl)
        #expect(oldUrl == url)
        #expect(sut.fileLocation(for: oldUrl!) == .local)
        #expect(try Data(contentsOf: oldUrl!).count == 4)

        try await sut.remove(url: url!)
        try await sut.remove(url: URL.documentsDirectory.appending(path: "TestsCopy"))
    }
}
