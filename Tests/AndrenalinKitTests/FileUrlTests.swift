// @copyright André Trettin

import Foundation
import Testing

@testable import AndrenalinKit

struct FileUrlTests {
    let fileId = UUID()
    let url = URL.documentsDirectory.appending(path: "Tests.txt")
    
    func setUp() async throws -> FileUrl {
        FileUrl(fileId: fileId, url: url, location: .local, module: "Tests", relativeUrl: LocationFileManager(moduleFolder: "Tests").relativeUrl(for: url))
    }

    @Test func fileUrl() async throws {
        let sut = try await setUp()
        #expect(sut.rawUrl == url)
        #expect(!sut.hasUnconvertedData)
        #expect(sut.location == .local)

        var tmp = sut
        tmp.resetData(Data(count: 4))
        #expect(tmp.hasUnconvertedData)
        
        #expect(sut.fileId == tmp.fileId)
        #expect(sut.rawUrl == tmp.rawUrl)
        #expect(sut.location == tmp.location)
        #expect(sut.module == tmp.module)
        #expect(sut.data != tmp.data)
    }
    
    @Test func fileUrlWithData() async throws {
        let dataFileUrl = FileUrl(string: "", fileId: fileId, module: nil, unconvertedData: Data(count: 4))
        #expect(nil != dataFileUrl)
        
        #expect(dataFileUrl!.fileId == fileId)
        #expect(dataFileUrl!.rawUrl == URL(filePath: ""))
        #expect(dataFileUrl!.hasUnconvertedData)
        #expect(dataFileUrl!.module == "ERROR")
    }

    @Test func fileUrlWithDataNil() async throws {
        let dataFileUrl = FileUrl(string: "", fileId: fileId, module: nil, unconvertedData: nil)
        #expect(nil == dataFileUrl)
    }
}
