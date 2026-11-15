// @copyright André Trettin

import Foundation
import Testing

@testable import SpaceRPG

/// CODE_AUDIT_26 §10.20: what the stale-scan cleanup removes and what it keeps.
@Suite("Scan folder cleanup")
struct ScanFolderCleanupTests {
    private func makeCapturesFolder() throws -> URL {
        let folder = URL.temporaryDirectory.appending(path: "Scans-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func makeScan(in captures: URL, models: [String] = [], images: Bool = true) throws -> URL {
        let scan = captures.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        for name in ["Images", "Snapshots", "Models"] {
            try FileManager.default.createDirectory(at: scan.appending(path: name, directoryHint: .isDirectory), withIntermediateDirectories: true)
        }
        if images {
            try Data([1]).write(to: scan.appending(path: "Images/IMG_0001.HEIC"))
            try Data([1]).write(to: scan.appending(path: "Snapshots/snap.png"))
        }
        for model in models {
            try Data([1]).write(to: scan.appending(path: "Models/\(model)"))
        }
        return scan
    }

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    @Test("A scan without a model is removed whole")
    func scanWithoutModelIsRemoved() throws {
        let captures = try makeCapturesFolder()
        defer { try? FileManager.default.removeItem(at: captures) }
        let scan = try makeScan(in: captures)

        ScanFolderCleanup.removeStaleScans(in: captures, createdBefore: .distantFuture)

        #expect(!exists(scan))
    }

    @Test("A scan with a model keeps the Models folder and loses only the raw photos")
    func scanWithModelKeepsModels() throws {
        let captures = try makeCapturesFolder()
        defer { try? FileManager.default.removeItem(at: captures) }
        let scan = try makeScan(in: captures, models: ["Crypt.usdz"])

        ScanFolderCleanup.removeStaleScans(in: captures, createdBefore: .distantFuture)

        #expect(exists(scan.appending(path: "Models/Crypt.usdz")))
        #expect(!exists(scan.appending(path: "Images")))
        #expect(!exists(scan.appending(path: "Snapshots")))
    }

    @Test("A folder created after the cutoff is not touched")
    func newerFolderIsKept() throws {
        let captures = try makeCapturesFolder()
        defer { try? FileManager.default.removeItem(at: captures) }
        let scan = try makeScan(in: captures)

        ScanFolderCleanup.removeStaleScans(in: captures, createdBefore: .distantPast)

        #expect(exists(scan.appending(path: "Images/IMG_0001.HEIC")))
    }

    @Test("Hidden files and an empty Models folder do not count as a model")
    func hiddenFilesAreNoModel() throws {
        let captures = try makeCapturesFolder()
        defer { try? FileManager.default.removeItem(at: captures) }
        let empty = try makeScan(in: captures)
        let hiddenOnly = try makeScan(in: captures, models: [".DS_Store"])

        #expect(ScanFolderCleanup.hasModelFiles(in: empty) == false)
        #expect(ScanFolderCleanup.hasModelFiles(in: hiddenOnly) == false)
    }

    @Test("A missing captures folder is a no-op")
    func missingFolderIsNoOp() {
        ScanFolderCleanup.removeStaleScans(in: URL.temporaryDirectory.appending(path: "NoSuchScans-\(UUID().uuidString)"), createdBefore: .distantFuture)
    }
}
