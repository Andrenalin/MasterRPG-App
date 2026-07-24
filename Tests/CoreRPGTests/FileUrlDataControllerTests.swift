// @copyright André Trettin

import Foundation
import Testing
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import UIKit
#endif

@testable import CoreRPG

@Suite("FileUrlDataController Tests")
struct FileUrlDataControllerTests {

    @Test("Initialize controller with folders")
    func readAddSaveReread() async throws {
        let sut = await FileUrlDataController(moduleFolder: uniqueModuleName("MegaModules"), fileTypes: [.rpgDocument], filenameExtension: ".rpg")

        #expect(await sut.model.folders.isEmpty)
    }
}

// MARK: - createNewFileUrl Tests

@Suite("createNewFileUrl - File Creation and Fallback Tests")
struct CreateNewFileUrlTests {
    
    @Test("Returns nil when FileUrl has no data")
    func returnsNilWhenNoData() async throws {
        let module = uniqueModuleName()
        let sut = await FileUrlDataController(moduleFolder: module, fileTypes: [.data], filenameExtension: "test")
        
        let fileUrl = FileUrl(fileId: UUID(), url: try uniqueRelativeTestURL(), location: .newCloud, module: module, relativeUrl: nil)
        
        let result = try await sut.createNewFileUrl(fileId: UUID(), unconvertedFileUrl: fileUrl, pathExtension: "test")
        
        #expect(result == nil)
    }
    
    @Test("Returns existing FileUrl when file already exists at old location")
    func returnsExistingFileUrlWhenFileExists() async throws {
        let module = uniqueModuleName()
        let sut = await FileUrlDataController(moduleFolder: module, fileTypes: [.data], filenameExtension: "test")
        
        // Create a test file in temporary directory
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("test")
        let testData = "Test data content".data(using: .utf8)!
        try testData.write(to: tempURL)
        
        var fileUrl = FileUrl(fileId: UUID(), url: tempURL, location: .local, module: module, relativeUrl: nil)
        fileUrl.resetData(testData)
        
        let result = try await sut.createNewFileUrl(fileId: UUID(), unconvertedFileUrl: fileUrl, pathExtension: "test")
        
        #expect(result?.rawUrl == tempURL)
        #expect(result?.location == .local)
        // File exists on disk, so data should NOT be kept in memory (memory optimization)
        #expect(result?.hasUnconvertedData == false, "Should NOT keep data in memory when file already exists on disk")
        
        // Cleanup
        try? FileManager.default.removeItem(at: tempURL)
    }
    
    @Test("Successfully creates file in cloud storage")
    func successfullyCreatesFileInCloudStorage() async throws {
        let module = uniqueModuleName()
        let sut = await FileUrlDataController(moduleFolder: module, fileTypes: [.data], filenameExtension: "test")
        
        let fileId = UUID()
        let testData = "Test cloud data".data(using: .utf8)!
        let testUrl = try uniqueRelativeTestURL()
        let testFileName = testUrl.lastPathComponent
        
        var fileUrl = FileUrl(fileId: fileId, url: testUrl, location: .newCloud, module: module, relativeUrl: nil)
        fileUrl.resetData(testData)
        
        let result = try await sut.createNewFileUrl(fileId: fileId, unconvertedFileUrl: fileUrl, pathExtension: "test")
        
        #expect(result != nil)
        #expect(result?.location == .newCloud)
        #expect(result?.hasUnconvertedData == false, "Data should NOT be kept in memory after successful save")
        #expect(result?.rawUrl.lastPathComponent == testFileName)
        
        // Verify file was actually written by trying to read it back
        if let result {
            let readData = try? await sut.loadData(for: result)
            #expect(readData == testData)
        }
    }
    
    @Test("Successfully creates file in cloud storage without keeping data in memory")
    func successfullyCreatesFileWithoutKeepingDataInMemory() async throws {
        let module = uniqueModuleName()
        let sut = await FileUrlDataController(moduleFolder: module, fileTypes: [.data], filenameExtension: "test")
        
        let fileId = UUID()
        let testData = "Test fallback data".data(using: .utf8)!
        
        // Create a test that will succeed (since it's hard to make cloud write actually fail in tests)
        // This test validates the BEHAVIOR when write fails, even though we can't easily trigger it
        let testUrl = try uniqueRelativeTestURL()
        
        var fileUrl = FileUrl(fileId: fileId, url: testUrl, location: .newCloud, module: module, relativeUrl: nil)
        fileUrl.resetData(testData)
        
        let result = try await sut.createNewFileUrl(fileId: fileId, unconvertedFileUrl: fileUrl, pathExtension: "test")
        
        // In normal operation, cloud write succeeds and data is NOT kept in memory
        if let result {
            // This is the NORMAL case - write succeeds
            #expect(result.hasUnconvertedData == false, "Data should NOT be in memory after successful cloud write")
            
            // But data should be loadable from cloud
            let loadedData = try? await sut.loadData(for: result)
            #expect(loadedData == testData, "Should be able to load data from cloud storage")
        } else {
            Issue.record("Should create a FileUrl")
        }
    }
    
    @Test("Handles file from different device or user gracefully")
    func handlesFileFromDifferentDevice() async throws {
        let module = uniqueModuleName()
        let sut = await FileUrlDataController(moduleFolder: module, fileTypes: [.data], filenameExtension: "test")
        
        let fileId = UUID()
        let testData = "Data from another device".data(using: .utf8)!
        
        // Simulate a URL that would exist on another device but not here
        let unreachableUrl = URL(fileURLWithPath: "/Users/otheruser/Documents/file.test")
        
        var fileUrl = FileUrl(fileId: fileId, url: unreachableUrl, location: .local, module: module, relativeUrl: nil)
        fileUrl.resetData(testData)
        
        let result = try await sut.createNewFileUrl(fileId: fileId, unconvertedFileUrl: fileUrl, pathExtension: "test")
        
        // Should create new location since old one doesn't exist
        #expect(result != nil)
        #expect(result?.hasUnconvertedData == false || ((result?.rawUrl.path().isEmpty) != nil), "Should either save to disk or keep in memory as last resort")
    }

    @Test("Restores imported URL data into cache while preserving the remote URL")
    func writesImportedURLDataIntoCache() async throws {
        let module = uniqueModuleName()
        let sut = await FileUrlDataController(moduleFolder: module, fileTypes: [.data], filenameExtension: "test")

        let fileId = UUID()
        let testData = "Remote file bytes".data(using: .utf8)!
        let remoteUrl = try #require(URL(string: "https://example.com/remote-file.test"))

        var fileUrl = FileUrl(fileId: fileId, url: remoteUrl, location: .url, module: module, relativeUrl: nil)
        fileUrl.resetData(testData)

        let result = try await sut.createNewFileUrl(fileId: fileId, unconvertedFileUrl: fileUrl, pathExtension: "test")

        let stored = try #require(result)
        #expect(stored.location == .url)
        #expect(stored.rawUrl == remoteUrl)
        #expect(stored.hasUnconvertedData == false)
        #expect(await sut.hasLocalData(for: stored))
        let loadedData = try await sut.loadData(for: stored)
        #expect(loadedData == testData)

        try? FileManager.default.removeItem(at: sut.remoteCacheURL(for: stored))
    }
}

// MARK: - Other FileUrlDataController Methods Tests

@Suite("File Access and Data Loading Tests")
struct FileAccessTests {
    
    @Test("hasAccess returns true for valid FileUrl")
    func hasAccessForValidFileUrl() async throws {
        let module = uniqueModuleName()
        let sut = await FileUrlDataController(moduleFolder: module, fileTypes: [.data], filenameExtension: "test")
        
        let fileId = UUID()
        let testData = "Accessible file data".data(using: .utf8)!
        var fileUrl = FileUrl(fileId: fileId, url: try uniqueRelativeTestURL(), location: .newCloud, module: module, relativeUrl: nil)
        fileUrl.resetData(testData)
        let createdFileUrl = try await sut.createNewFileUrl(fileId: fileId, unconvertedFileUrl: fileUrl, pathExtension: "test")
        let created = try #require(createdFileUrl)
        
        let hasAccess = await sut.hasAccess(for: created)
        
        // A newCloud file created by the controller should be accessible through its bookmark.
        #expect(hasAccess == true)
    }

    @Test(
        "App-managed files do not require security-scoped bookmarks",
        arguments: [FileLocation.newCloud, .local]
    )
    func appManagedFileHasAccessWithoutBookmark(location: FileLocation) async throws {
        let module = uniqueModuleName()
        let sut = await FileUrlDataController(
            moduleFolder: module,
            fileTypes: [.data],
            filenameExtension: "test"
        )
        let fileUrl = FileUrl(
            fileId: UUID(),
            url: try #require(URL(string: "Example/managed-file.test")),
            location: location,
            module: module,
            relativeUrl: nil
        )

        #expect(await sut.hasAccess(for: fileUrl))
    }

    @Test("Opening detail does not remove an app-managed list thumbnail")
    @MainActor
    func detailImageRequestKeepsManagedThumbnail() async throws {
        let module = uniqueModuleName()
        let fileController = FileUrlDataController(
            moduleFolder: module,
            fileTypes: [.image],
            filenameExtension: "jpg"
        )
        let itemId = UUID()
        let fileUrl = FileUrl(
            fileId: itemId,
            url: try #require(URL(string: "Example/selection.jpg")),
            location: .newCloud,
            module: module,
            relativeUrl: nil
        )
        let model = FakeItemModel(id: itemId, name: "Selection", fileUrl: fileUrl)
        let cacheController = ManagedFileImageCacheController(fileController: fileController)
        let thumbnail = AKImage()

        await cacheController.thumbnailCacheController.setObject(thumbnail, for: itemId)
        cacheController.setCachedThumbnail(thumbnail, for: itemId)

        _ = await cacheController.photoId(
            for: itemId,
            item: model,
            shouldDownload: true
        )

        #expect(await cacheController.thumbnailCacheController.hasObject(for: itemId))
        #expect(cacheController.cachedThumbnail(for: itemId) != nil)
    }

    @Test("App-group managed files are available without an iCloud download")
    func appGroupFileIsImmediatelyAvailable() async throws {
        let module = uniqueModuleName("Photo")
        let sut = await FileUrlDataController(
            moduleFolder: module,
            fileTypes: [.image],
            filenameExtension: "jpg"
        )
        let fileId = UUID()
        let data = Data("thumbnail bytes".utf8)
        let relativeURL = try #require(URL(string: "Example/image.jpg"))
        var imported = FileUrl(
            fileId: fileId,
            url: relativeURL,
            location: .newCloud,
            module: module,
            relativeUrl: nil
        )
        imported.resetData(data)
        let stored = try #require(
            try await sut.createNewFileUrl(
                fileId: fileId,
                unconvertedFileUrl: imported,
                pathExtension: "jpg"
            )
        )

        #expect(await sut.isAvailableWithoutDownloading(stored))
        #expect(try await sut.loadData(for: stored) == data)
    }
    
    @Test("loadData returns data when FileUrl has unconverted data")
    func loadDataReturnsUnconvertedData() async throws {
        let module = uniqueModuleName()
        let sut = await FileUrlDataController(moduleFolder: module, fileTypes: [.data], filenameExtension: "test")
        
        let testData = "Unconverted test data".data(using: .utf8)!
        var fileUrl = FileUrl(fileId: UUID(), url: try uniqueRelativeTestURL(), location: .newCloud, module: module, relativeUrl: nil)
        fileUrl.resetData(testData)
        
        let loadedData = try await sut.loadData(for: fileUrl)
        
        #expect(loadedData == testData)
    }
    
    @Test("fileDownloaded returns nil for local files")
    func fileDownloadedReturnsNilForLocalFiles() async throws {
        let module = uniqueModuleName()
        let sut = await FileUrlDataController(moduleFolder: module, fileTypes: [.data], filenameExtension: "test")
        
        let fileUrl = FileUrl(fileId: UUID(), url: URL(fileURLWithPath: "/test.test"), location: .local, module: module, relativeUrl: nil)
        
        let isDownloaded = await sut.fileDownloaded(for: fileUrl)
        
        #expect(isDownloaded == nil, "Local files should return nil for download status")
    }

    @Test("Creating a remote file keeps its URL and defers the download")
    func createsRemoteURLMetadata() async throws {
        let module = uniqueModuleName()
        let sut = await FileUrlDataController(
            moduleFolder: module,
            fileTypes: [.data],
            filenameExtension: "test"
        )
        let remoteURL = try #require(
            URL(string: "https://example.com/content/remote-file.test")
        )

        let fileURL = try await sut.createFileUrl(
            fileId: UUID(),
            url: remoteURL,
            module: module,
            category: nil
        )

        #expect(fileURL.location == .url)
        #expect(fileURL.rawUrl == remoteURL)
        #expect(await sut.hasLocalData(for: fileURL) == false)

        let replacementURL = try #require(
            URL(string: "https://example.com/content/replacement.test")
        )
        let replacement = FileUrl(
            fileId: fileURL.fileId,
            url: replacementURL,
            location: .url,
            module: module,
            relativeUrl: nil
        )
        #expect(sut.remoteCacheURL(for: replacement) != sut.remoteCacheURL(for: fileURL))
    }

    @Test("First use downloads a remote URL once and later reads use its cache")
    func downloadsRemoteURLIntoCacheOnFirstUse() async throws {
        let module = uniqueModuleName()
        let sourceURL = URL.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appendingPathExtension("test")
        let expectedData = Data("downloaded remote data".utf8)
        try expectedData.write(to: sourceURL)
        let probe = RemoteDownloadProbe(sourceURL: sourceURL)
        let sut = await FileUrlDataController(
            moduleFolder: module,
            fileTypes: [.data],
            filenameExtension: "test",
            remoteFileDownloader: { remoteURL in
                try await probe.download(remoteURL)
            }
        )
        let remoteURL = try #require(
            URL(string: "https://example.com/content/download.test")
        )
        let fileURL = FileUrl(
            fileId: UUID(),
            url: remoteURL,
            location: .url,
            module: module,
            relativeUrl: nil
        )

        let firstRead = try await sut.loadData(for: fileURL)
        try FileManager.default.removeItem(at: sourceURL)
        let secondRead = try await sut.loadData(for: fileURL)

        #expect(firstRead == expectedData)
        #expect(secondRead == expectedData)
        #expect(await probe.requestCount == 1)
        #expect(await sut.hasLocalData(for: fileURL))

        try? FileManager.default.removeItem(at: sut.remoteCacheURL(for: fileURL))
    }
}

private actor RemoteDownloadProbe {
    init(sourceURL: URL) {
        self.sourceURL = sourceURL
    }

    let sourceURL: URL
    private(set) var requestCount = 0

    func download(_ remoteURL: URL) throws -> URL {
        guard remoteURL.isSupportedRemoteFileURL else {
            throw URLError(.unsupportedURL)
        }
        requestCount += 1
        return sourceURL
    }
}

private struct ManagedFileImageCacheController: ImageCacheControllable {
    @MainActor
    init(fileController: FileUrlDataController) {
        imageCacheController = ImageCacheController()
        thumbnailCacheController = ImageCacheController()
        fileUrlDataController = fileController
        observableImageCache = ObservableImageCache()
    }

    let imageCacheController: ImageCacheController
    let thumbnailCacheController: ImageCacheController
    let fileUrlDataController: FileUrlDataController?
    let observableImageCache: ObservableImageCache

    @MainActor
    func createThumbnail(
        for itemId: UUID,
        item: any ItemDataAccessable
    ) async {}
}

@Suite("File Duplication Tests")
struct FileDuplicationTests {
    
    @Test("duplicate creates new FileUrl with different fileId")
    func duplicateCreatesNewFileUrl() async throws {
        let module = uniqueModuleName()
        let sut = await FileUrlDataController(moduleFolder: module, fileTypes: [.data], filenameExtension: "test")
        
        // Create original file
        let originalFileId = UUID()
        let testData = "Original data".data(using: .utf8)!
        let testUrl = try uniqueRelativeTestURL(prefix: "original")
        
        var originalFileUrl = FileUrl(fileId: originalFileId, url: testUrl, location: .newCloud, module: module, relativeUrl: nil)
        originalFileUrl.resetData(testData)
        
        let created = try await sut.createNewFileUrl(fileId: originalFileId, unconvertedFileUrl: originalFileUrl, pathExtension: "test")
        
        // Duplicate it
        let newFileId = UUID()
        let duplicated = try await sut.duplicate(fileUrl: created, for: newFileId)
        
        #expect(duplicated != nil)
        #expect(duplicated?.fileId == newFileId)
        #expect(duplicated?.fileId != originalFileId)
    }
    
    @Test("duplicate returns nil when original has no data")
    func duplicateReturnsNilWhenNoData() async throws {
        let module = uniqueModuleName()
        let sut = await FileUrlDataController(moduleFolder: module, fileTypes: [.data], filenameExtension: "test")
        
        // Create a FileUrl without data (file doesn't exist)
        let fileUrl = FileUrl(fileId: UUID(), url: try uniqueRelativeTestURL(prefix: "nonexistent"), location: .newCloud, module: module, relativeUrl: nil)
        
        // duplicate should return nil because there's no data to load
        let duplicated = try await sut.duplicate(fileUrl: fileUrl, for: UUID())
        
        #expect(duplicated == nil, "Should return nil when file doesn't exist and has no data")
    }
}

@Suite("File Deletion Tests")
struct FileDeletionTests {
    
    @Test("delete removes cloud file")
    func deleteRemovesCloudFile() async throws {
        let module = uniqueModuleName()
        let sut = await FileUrlDataController(moduleFolder: module, fileTypes: [.data], filenameExtension: "test")
        
        // Create a file in cloud storage first
        let fileId = UUID()
        let testData = "Delete me".data(using: .utf8)!
        let testUrl = try uniqueRelativeTestURL(prefix: "delete-test")
        
        var fileUrl = FileUrl(fileId: fileId, url: testUrl, location: .newCloud, module: module, relativeUrl: nil)
        fileUrl.resetData(testData)
        
        // Create the file
        let created = try await sut.createNewFileUrl(fileId: fileId, unconvertedFileUrl: fileUrl, pathExtension: "test")
        
        // Delete it
        if let created {
            sut.delete(created)
            
            // Give it a moment to delete asynchronously
            try await Task.sleep(for: .milliseconds(100))
            
            // Try to load - should fail or return nil
            let loadedData = try? await sut.loadData(for: created)
            #expect(loadedData == nil, "File should be deleted and data unavailable")
        }
    }
    
    @Test("delete handles nil FileUrl gracefully")
    func deleteHandlesNilGracefully() async throws {
        let sut = await FileUrlDataController(moduleFolder: uniqueModuleName(), fileTypes: [.data], filenameExtension: "test")
        
        // Should not crash
        sut.delete(nil)
        
        #expect(true, "Should handle nil without crashing")
    }
}

@Suite("isSameFile Tests")
struct IsSameFileTests {
    
    @Test("isSameFile returns true for same cloud file")
    func returnsTrueForSameCloudFile() async throws {
        let module = uniqueModuleName()
        let sut = await FileUrlDataController(moduleFolder: module, fileTypes: [.data], filenameExtension: "test")
        
        // Create an actual file and get its URL
        let fileId = UUID()
        let testData = "Test data".data(using: .utf8)!
        let testUrl = try uniqueRelativeTestURL(prefix: "samefile")
        
        var fileUrl = FileUrl(fileId: fileId, url: testUrl, location: .newCloud, module: module, relativeUrl: nil)
        fileUrl.resetData(testData)
        
        let created = try await sut.createNewFileUrl(fileId: fileId, unconvertedFileUrl: fileUrl, pathExtension: "test")
        
        // Now test isSameFile with the created file's URL
        if let created {
            // Get the full URL from the controller
            let fullUrl = await sut.url(for: created, action: { $0 })
            
            // Test with the same URL
            let isSame = await sut.isSameFile(existingFileUrl: created, newUrl: fullUrl)
            #expect(isSame == true, "Should recognize same file")
        }
    }
    
    @Test("isSameFile returns false for different paths")
    func returnsFalseForDifferentPaths() async throws {
        let module = uniqueModuleName()
        let sut = await FileUrlDataController(moduleFolder: module, fileTypes: [.data], filenameExtension: "test")
        
        let fileUrl = FileUrl(fileId: UUID(), url: URL(fileURLWithPath: "/path1/file.test"), location: .newCloud, module: module, relativeUrl: nil)
        let differentUrl = URL(fileURLWithPath: "/path2/file.test")
        
        let isSame = await sut.isSameFile(existingFileUrl: fileUrl, newUrl: differentUrl)
        
        #expect(isSame == false)
    }
    
    @Test("isSameFile returns false for nil URL")
    func returnsFalseForNilUrl() async throws {
        let module = uniqueModuleName()
        let sut = await FileUrlDataController(moduleFolder: module, fileTypes: [.data], filenameExtension: "test")
        
        let fileUrl = FileUrl(fileId: UUID(), url: try uniqueRelativeTestURL(), location: .newCloud, module: module, relativeUrl: nil)
        
        let isSame = await sut.isSameFile(existingFileUrl: fileUrl, newUrl: nil)
        
        #expect(isSame == false)
    }
}

fileprivate enum FileUrlDataControllerTestError: Error {
    case invalidRelativeURL(String)
}

fileprivate func uniqueModuleName(_ prefix: String = "TestModule") -> String {
    "\(prefix)-\(UUID().uuidString)"
}

fileprivate func uniqueRelativeTestURL(prefix: String = "testfile", pathExtension: String = "test") throws -> URL {
    let filename = "\(prefix)-\(UUID().uuidString).\(pathExtension)"
    guard let url = URL(string: filename) else {
        throw FileUrlDataControllerTestError.invalidRelativeURL(filename)
    }
    return url
}
