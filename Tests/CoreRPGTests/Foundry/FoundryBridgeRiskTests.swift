// @copyright André Trettin

import Foundation
import Testing

@testable import CoreRPG

/// CODE_AUDIT_26 §10.9: bridge-file risks, each with a time limit so a regression to quadratic
/// work fails instead of hanging.
@Suite("Foundry bridge risks")
struct FoundryBridgeRiskTests {
    private static let manifest = #"{"record":"manifest","format":"masterrpg-foundry-bridge","version":1,"source":{"kind":"selection","id":"demo","title":"Demo"},"documentCount":0,"assetCount":0}"#
    private static let end = #"{"record":"end","documentCount":0,"assetCount":0}"#

    private func write(_ lines: [String]) throws -> (url: URL, directory: URL) {
        let directory = URL.temporaryDirectory.appending(path: "FoundryBridgeRisk-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "selection.mrpgfoundry")
        try Data(lines.joined(separator: "\n").utf8).write(to: url)
        return (url, directory)
    }

    @Test("Malformed asset references are skipped with a capped diagnostic and the import continues", .timeLimit(.minutes(1)))
    func malformedAssetReferencesDoNotAbortTheImport() async throws {
        let malformed = [
            #"{"record":"assetReference","status":"missing"}"#,
            #"{"record":"assetReference","path":"maps/a.png"}"#,
            #"{"record":"assetReference","path":"../../escape.png","status":"missing"}"#,
            #"{"record":"assetReference","path":42,"status":"missing"}"#
        ]
        let (url, directory) = try write([Self.manifest] + malformed + [Self.end])
        defer { try? FileManager.default.removeItem(at: directory) }

        let package = try await FoundryVTTImportReader().read(from: url)

        #expect(package.diagnostics.contains { $0.code == "invalid-bridge-asset-reference" })
    }

    @Test("Thousands of malformed references stay within the diagnostic cap", .timeLimit(.minutes(1)))
    func manyMalformedReferencesAreCapped() async throws {
        let malformed = Array(repeating: #"{"record":"assetReference","status":"missing"}"#, count: 3_000)
        let (url, directory) = try write([Self.manifest] + malformed + [Self.end])
        defer { try? FileManager.default.removeItem(at: directory) }

        let package = try await FoundryVTTImportReader().read(from: url)

        #expect(package.diagnostics.count < 3_000)
    }

    @Test("A bridge file over the byte limit is refused before it is decoded", .timeLimit(.minutes(1)))
    func oversizedBridgeFileIsRefusedEarly() async throws {
        let (url, directory) = try write([Self.manifest, Self.end])
        defer { try? FileManager.default.removeItem(at: directory) }
        let reader = FoundryVTTImportReader(limits: FoundryImportLimits(maximumRuleDataSize: 16))

        await #expect(throws: FoundryImportError.self) {
            _ = try await reader.read(from: url)
        }
    }
}
