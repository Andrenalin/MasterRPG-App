// @copyright André Trettin

import Foundation
import Testing

@testable import CoreRPG

@Suite("General Foundry VTT import transport")
struct FoundryVTTImportReaderTests {
    @Test("Reads legacy NeDB documents and embedded families")
    func readsLegacyDatabase() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "actors.db")
        let rows = [
            #"{"_id":"deleted","name":"Old","type":"character","system":{}}"#,
            #"{"_id":"deleted","$$deleted":true}"#,
            #"{"_id":"hero","name":"Hero","type":"character","img":"icons/hero.webp","system":{"description":"<p>Hero</p>","future":7},"items":[{"_id":"sword","name":"Sword","type":"weapon","system":{}}],"effects":[{"_id":"bless","name":"Bless"}]}"#,
        ]
        try Data(rows.joined(separator: "\n").utf8).write(to: url)

        let package = try await FoundryVTTImportReader().read(from: url)

        #expect(package.kind == .documentCollection)
        #expect(package.documents.count == 1)
        #expect(package.documents.first?.documentType == .actor)
        #expect(package.documents.first?.embeddedDocuments.map(\.documentType).sorted(by: { $0.rawValue < $1.rawValue }) == [.activeEffect, .item])
        #expect(package.statistics.topLevelDocumentCount == 1)
        #expect(package.statistics.embeddedDocumentCount == 2)
        #expect(package.resources.first?.logicalPath == "icons/hero.webp")
        #expect(package.resources.first?.location == .foundryInstallation)
    }

    @Test("Bounds NeDB records and repeated malformed-record diagnostics")
    func boundsLegacyRecordAndDiagnostics() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let boundedURL = directory.appending(path: "bounded.db")
        // Empty and malformed physical lines both consume the transport-record budget.
        try Data("\nnot-json\nstill-invalid".utf8).write(to: boundedURL)
        let recordBoundedReader = FoundryVTTImportReader(limits: FoundryImportLimits(
            maximumRecordCount: 2
        ))

        await #expect(throws: FoundryImportError.tooManyDocuments(3)) {
            _ = try await recordBoundedReader.read(from: boundedURL)
        }

        let diagnosticURL = directory.appending(path: "diagnostics.db")
        let lines = [
            "not-json",
            "also-invalid",
            "still-invalid",
            #"{"_id":"hero","name":"Hero","type":"character","system":{}}"#,
        ]
        try Data(lines.joined(separator: "\n").utf8).write(to: diagnosticURL)
        let diagnosticBoundedReader = FoundryVTTImportReader(limits: FoundryImportLimits(
            maximumRecordCount: 4,
            maximumDiagnosticCount: 1
        ))

        let package = try await diagnosticBoundedReader.read(from: diagnosticURL)

        #expect(package.documents.count == 1)
        #expect(package.diagnostics.count == 2)
        #expect(package.diagnostics.filter { $0.code == "invalid-nedb-record" }.isEmpty)
        #expect(package.diagnostics.contains { $0.code == "diagnostics-truncated" })
        #expect(package.diagnostics.contains { $0.code == "documents-decoded" })

        let zeroDiagnosticReader = FoundryVTTImportReader(limits: FoundryImportLimits(
            maximumRecordCount: 4,
            maximumDiagnosticCount: 0
        ))
        let zeroDiagnosticPackage = try await zeroDiagnosticReader.read(from: diagnosticURL)
        #expect(zeroDiagnosticPackage.diagnostics.map(\.code) == ["documents-decoded"])
    }

    @Test("Bounds manifest-declared pack counts instead of building an unbounded spec list")
    func boundsManifestPackDeclarations() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        // CODE_AUDIT §5.9: a tiny, well-formed manifest could otherwise declare
        // millions of bogus packs with no cap, each going on to cost real work.
        let packs = (0..<10).map { #"{"name":"pack-\#($0)","type":"Item"}"# }.joined(separator: ",")
        let manifest = #"{"id":"bounds-test","title":"Bounds Test","packs":[\#(packs)]}"#
        try Data(manifest.utf8).write(to: directory.appending(path: "module.json"))
        let reader = FoundryVTTImportReader(limits: FoundryImportLimits(maximumDocumentCount: 5))

        await #expect(throws: FoundryImportError.tooManyDocuments(6)) {
            _ = try await reader.read(from: directory)
        }
    }

    @Test("Infers a standalone exported RollTable conservatively")
    func readsStandaloneJSON() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "mystery.json")
        try Data(#"{"_id":"table","name":"Weather","formula":"1d2","replacement":true,"results":[{"_id":"rain","text":"Rain","range":[1,1]}],"futureField":{"kept":true}}"#.utf8).write(to: url)

        let package = try await FoundryVTTImportReader().read(from: url)

        let document = try #require(package.documents.first)
        #expect(document.documentType == .rollTable)
        #expect(document.embeddedDocuments.first?.documentType == .tableResult)
        #expect(document.rawData.value(at: "futureField.kept")?.boolValue == true)
        #expect(document.unknownFieldNames.contains("futureField"))
    }

    @Test("Standalone JSON and NeDB canonical IDs survive source-file renames")
    func standaloneCanonicalIDsSurviveRenames() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let reader = FoundryVTTImportReader()

        let originalJSON = directory.appending(path: "weather-export.json")
        let renamedJSON = directory.appending(path: "renamed-export.json")
        try Data(
            #"{"_id":"weather","documentName":"RollTable","name":"Weather","formula":"1d2","results":[]}"#.utf8
        ).write(to: originalJSON)
        let originalJSONID = try #require(try await reader.read(from: originalJSON).documents.first?.id)
        try FileManager.default.moveItem(at: originalJSON, to: renamedJSON)
        let renamedJSONPackage = try await reader.read(from: renamedJSON)

        let originalDatabase = directory.appending(path: "actors.db")
        let renamedDatabase = directory.appending(path: "renamed.db")
        try Data(
            #"{"_id":"hero","name":"Hero","type":"character","system":{},"items":[]}"#.utf8
        ).write(to: originalDatabase)
        let originalDatabaseID = try #require(
            try await reader.read(from: originalDatabase).documents.first?.id
        )
        try FileManager.default.moveItem(at: originalDatabase, to: renamedDatabase)
        let renamedDatabasePackage = try await reader.read(from: renamedDatabase)

        #expect(renamedJSONPackage.documents.first?.id == originalJSONID)
        #expect(renamedJSONPackage.collections.first?.id == "standalone")
        #expect(renamedDatabasePackage.documents.first?.id == originalDatabaseID)
        #expect(renamedDatabasePackage.collections.first?.id == "standalone")
    }

    @Test("Selected LevelDB canonical IDs survive database-directory renames")
    func selectedLevelDBCanonicalIDsSurviveDirectoryRename() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let originalDatabase = directory.appending(path: "original-database", directoryHint: .isDirectory)
        let renamedDatabase = directory.appending(path: "renamed-database", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: originalDatabase, withIntermediateDirectories: true)
        let actor = Data(
            #"{"_id":"hero","name":"Hero","type":"character","system":{},"items":[]}"#.utf8
        )
        let table = FoundryLevelDBFixture.table(records: [
            FoundryLevelDBRecord(
                key: "!actors!hero",
                sequence: 1,
                operation: .value,
                value: actor
            ),
        ])
        try table.write(to: originalDatabase.appending(path: "000001.ldb"))
        let reader = FoundryVTTImportReader()

        let originalPackage = try await reader.read(from: originalDatabase)
        try FileManager.default.moveItem(at: originalDatabase, to: renamedDatabase)
        let renamedPackage = try await reader.read(from: renamedDatabase)

        #expect(renamedPackage.documents.map(\.id) == originalPackage.documents.map(\.id))
        #expect(renamedPackage.collections.first?.id == "standalone")
    }

    @Test("Manifest pack identity prevents same-type document collisions")
    func manifestPackIdentitySeparatesDocuments() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let packs = directory.appending(path: "packs", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: packs, withIntermediateDirectories: true)
        let manifest = #"{"id":"identity-test","title":"Identity Test","packs":[{"name":"first","path":"packs/first.db","type":"Item"},{"name":"second","path":"packs/second.db","type":"Item"}]}"#
        try Data(manifest.utf8).write(to: directory.appending(path: "system.json"))
        let item = #"{"_id":"shared","name":"Shared","type":"equipment","system":{}}"#
        try Data(item.utf8).write(to: packs.appending(path: "first.db"))
        try Data(item.utf8).write(to: packs.appending(path: "second.db"))

        let package = try await FoundryVTTImportReader().read(from: directory)
        let ids = package.documents.map(\.id)

        #expect(ids.count == 2)
        #expect(Set(ids).count == 2)
        #expect(ids.contains { $0.contains("/collection/first/") })
        #expect(ids.contains { $0.contains("/collection/second/") })
    }

    @Test("Reads Foundry v14 Scene Levels as embedded documents")
    func readsSceneLevels() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "scene.json")
        let json = #"{"_id":"scene","documentName":"Scene","name":"Tower","initialLevel":"ground","width":1000,"height":800,"levels":[{"_id":"basement","name":"Basement","elevation":{"bottom":-10,"top":0},"background":{"src":"maps/basement.webp"},"walls":[{"_id":"cell-wall","c":[0,0,10,0]}]},{"_id":"ground","name":"Ground","elevation":{"bottom":0,"top":10},"background":{"src":"maps/ground.webp"}}],"tokens":[{"_id":"hero","name":"Hero","level":"ground"}]}"#
        try Data(json.utf8).write(to: url)

        let package = try await FoundryVTTImportReader().read(from: url)
        let scene = try #require(package.documents.first)
        let levels = scene.embeddedDocuments.filter { $0.documentType == .level }

        #expect(levels.map(\.documentID).sorted() == ["basement", "ground"])
        #expect(levels.first { $0.documentID == "basement" }?.rawData.value(at: "elevation.bottom")?.integerValue == -10)
        #expect(levels.first { $0.documentID == "basement" }?.embeddedDocuments.first?.documentType == .wall)
        #expect(scene.embeddedDocuments.contains { $0.documentType == .token })
        #expect(package.resources.contains { $0.logicalPath == "maps/basement.webp" })
    }

    @Test("Collects image, PDF, and audio references from Journal HTML")
    func collectsJournalHTMLAssets() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeDirectFoundryPackage(
            at: directory,
            collection: "journals",
            document: [
                "_id": "journal",
                "name": "Journal",
                "content": #"<p><img src="images/portrait.png"><a HREF = 'handouts/rules.pdf'>Rules</a><audio src=audio/theme.mp3></audio><img src="https://example.invalid/remote.webp"><img src="data:image/png;base64,AAAA"></p>"#,
            ]
        )
        try writeFoundryAsset(Data("image".utf8), path: "images/portrait.png", in: directory)
        try writeFoundryAsset(Data("pdf".utf8), path: "handouts/rules.pdf", in: directory)
        try writeFoundryAsset(Data("audio".utf8), path: "audio/theme.mp3", in: directory)

        let package = try await FoundryVTTImportReader().read(from: directory)
        let resources = Dictionary(uniqueKeysWithValues: package.resources.map { ($0.logicalPath, $0) })

        #expect(resources["images/portrait.png"]?.location == .packaged)
        #expect(resources["handouts/rules.pdf"]?.location == .packaged)
        #expect(resources["audio/theme.mp3"]?.location == .packaged)
        #expect(resources["https://example.invalid/remote.webp"]?.location == .remote)
        #expect(resources["https://example.invalid/remote.webp"]?.packagePath == nil)
        #expect(!package.resources.contains { $0.logicalPath.hasPrefix("data:") })
    }

    @Test("Percent-decodes packaged asset paths before safe normalization")
    func resolvesPercentEncodedAssetPath() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let expected = Data("encoded-space".utf8)
        try writeDirectFoundryPackage(
            at: directory,
            collection: "actors",
            document: [
                "_id": "hero",
                "name": "Hero",
                "img": "maps/My%20Map.webp",
            ]
        )
        try writeFoundryAsset(expected, path: "maps/My Map.webp", in: directory)
        let reader = FoundryVTTImportReader()

        let package = try await reader.read(from: directory)
        let resource = try #require(package.resources.first { $0.logicalPath == "maps/My%20Map.webp" })
        let reopened = try await reader.resourceData(for: resource, from: directory)

        #expect(resource.location == .packaged)
        #expect(resource.packagePath == "maps/My Map.webp")
        #expect(reopened.data == expected)
    }

    @Test("Collects every additional mapper-supported media extension", arguments: [
        "apng", "bmp", "tif", "tiff", "aif", "aiff", "caf",
    ])
    func collectsAdditionalMapperMediaExtensions(fileExtension: String) async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = "assets/example.\(fileExtension)"
        try writeDirectFoundryPackage(
            at: directory,
            collection: "journals",
            document: [
                "_id": "journal",
                "name": "Journal",
                "asset": path,
            ]
        )
        try writeFoundryAsset(Data(fileExtension.utf8), path: path, in: directory)

        let package = try await FoundryVTTImportReader().read(from: directory)
        let resource = try #require(package.resources.first { $0.logicalPath == path })

        #expect(resource.location == .packaged)
        #expect(resource.packagePath == path)
    }

    @Test("Leaves percent-encoded traversal references unresolved")
    func rejectsPercentEncodedAssetTraversal() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let reference = "maps/%2e%2e/secret.pdf"
        try writeDirectFoundryPackage(
            at: directory,
            collection: "journals",
            document: [
                "_id": "journal",
                "name": "Journal",
                "content": #"<a href="maps/%2e%2e/secret.pdf">Secret</a>"#,
            ]
        )
        try writeFoundryAsset(Data("must-not-resolve".utf8), path: "secret.pdf", in: directory)
        let reader = FoundryVTTImportReader()

        let package = try await reader.read(from: directory)
        let resource = try #require(package.resources.first { $0.logicalPath == reference })

        #expect(resource.location == .unresolved)
        #expect(resource.packagePath == nil)
        await #expect(throws: FoundryImportError.self) {
            _ = try await reader.resourceData(for: resource, from: directory)
        }
    }

    @Test("Rejects duplicate top-level canonical document identifiers")
    func rejectsDuplicateTopLevelDocumentIdentifiers() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "duplicate-scenes.json")
        let json = #"[{"_id":"same","documentName":"Scene","name":"First"},{"_id":"same","documentName":"Scene","name":"Second"}]"#
        try Data(json.utf8).write(to: url)

        await #expect(throws: FoundryImportError.self) {
            _ = try await FoundryVTTImportReader().read(from: url)
        }
    }

    @Test("Rejects duplicate embedded canonical document identifiers")
    func rejectsDuplicateEmbeddedDocumentIdentifiers() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "duplicate-actor.json")
        let json = #"{"_id":"actor","documentName":"Actor","name":"Hero","items":[{"_id":"same","name":"Sword"},{"_id":"same","name":"Shield"}]}"#
        try Data(json.utf8).write(to: url)

        await #expect(throws: FoundryImportError.self) {
            _ = try await FoundryVTTImportReader().read(from: url)
        }
    }

    @Test("Merges current LevelDB values across tables")
    func mergesLevelDBRecords() throws {
        let current = try FoundryLevelDBRecordMerger.currentRecords([
            FoundryLevelDBRecord(key: "!items!a", sequence: 1, operation: .value, value: Data("old".utf8)),
            FoundryLevelDBRecord(key: "!items!b", sequence: 2, operation: .value, value: Data("deleted".utf8)),
            FoundryLevelDBRecord(key: "!items!a", sequence: 3, operation: .value, value: Data("new".utf8)),
            FoundryLevelDBRecord(key: "!items!b", sequence: 4, operation: .deletion, value: Data()),
        ])

        #expect(current == [
            FoundryLevelDBRecord(key: "!items!a", sequence: 3, operation: .value, value: Data("new".utf8)),
        ])
        #expect(throws: FoundryImportError.self) {
            try FoundryLevelDBRecordMerger.currentRecords([
                FoundryLevelDBRecord(key: "!items!a", sequence: 7, operation: .value, value: Data("one".utf8)),
                FoundryLevelDBRecord(key: "!items!a", sequence: 7, operation: .value, value: Data("two".utf8)),
            ])
        }
    }

    @Test("Reads the live multi-table set from a LevelDB MANIFEST")
    func readsLevelDBManifest() throws {
        let firstEdit = manifestEdit(adding: [1, 2], deleting: [])
        let secondEdit = manifestEdit(adding: [3], deleting: [1])
        let manifest = Data(manifestRecord(firstEdit) + manifestRecord(secondEdit))

        let active = try FoundryLevelDBManifestReader().activeFileNumbers(in: manifest)

        #expect(active == Set([2, 3]))
        var corrupted = manifest
        corrupted[0] ^= 0xff
        #expect(throws: FoundryImportError.self) {
            try FoundryLevelDBManifestReader().activeFileNumbers(in: corrupted)
        }
    }

    @Test("Reads bridge documents and lazily verifies included assets")
    func readsBridgeAndResource() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "world.mrpgfoundry")
        let image = validPNGHeader()
        let hash = foundrySHA256(image)
        let lines = [
            #"{"record":"manifest","format":"masterrpg-foundry-bridge","version":1,"exportedAt":"2026-07-20T00:00:00Z","foundryVersion":"14.0","source":{"kind":"world","id":"demo","title":"Demo","systemID":"ds4","systemVersion":"2"},"documentCount":1,"assetCount":1}"#,
            #"{"record":"document","collection":"scenes","documentType":"Scene","uuid":"Scene.scene","parentUUID":null,"data":{"_id":"scene","name":"Dungeon","width":100,"height":100,"tokens":[{"_id":"token","name":"Hero"}],"background":{"src":"maps/dungeon.png"}}}"#,
            #"{"record":"asset","path":"maps/dungeon.png","mediaType":"image/png","sha256":"\#(hash)","encoding":"base64","data":"\#(image.base64EncodedString())"}"#,
            #"{"record":"assetReference","path":"maps/missing.png","status":"missing","reason":"Unavailable"}"#,
            #"{"record":"future-record","value":true}"#,
            #"{"record":"end","documentCount":1,"assetCount":1}"#,
        ]
        try Data(lines.joined(separator: "\n").utf8).write(to: url)

        let reader = FoundryVTTImportReader()
        let package = try await reader.read(from: url)
        let resource = try #require(package.resources.first)
        let reopened = try await reader.resourceData(for: resource, from: url)
        let batch = try await reader.readResources([resource], from: url, in: package)

        #expect(package.kind == .world)
        #expect(package.documents.first?.documentType == .scene)
        #expect(package.documents.first?.sourceUUID == "Scene.scene")
        #expect(package.documents.first?.embeddedDocuments.first?.documentType == .token)
        #expect(package.diagnostics.contains { $0.code == "unknown-bridge-record" })
        #expect(reopened.data == image)
        #expect(batch.first?.data == image)
    }

    @Test("Bounds bridge records and repeated unknown-record diagnostics")
    func boundsBridgeRecordsAndDiagnostics() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let boundedLines = [
            #"{"record":"manifest","format":"masterrpg-foundry-bridge","version":1,"source":{"kind":"selection","id":"demo","title":"Demo"},"documentCount":0,"assetCount":0}"#,
            "",
            #"{"record":"future-one"}"#,
            #"{"record":"future-two"}"#,
            "not-json",
            #"{"record":"end","documentCount":0,"assetCount":0}"#,
        ]
        let boundedURL = directory.appending(path: "bounded.mrpgfoundry")
        try Data(boundedLines.joined(separator: "\n").utf8).write(to: boundedURL)
        let recordBoundedReader = FoundryVTTImportReader(limits: FoundryImportLimits(
            maximumRecordCount: 4
        ))

        await #expect(throws: FoundryImportError.tooManyDocuments(5)) {
            _ = try await recordBoundedReader.read(from: boundedURL)
        }

        let diagnosticURL = directory.appending(path: "diagnostics.mrpgfoundry")
        let diagnosticLines = [
            #"{"record":"manifest","format":"masterrpg-foundry-bridge","version":1,"source":{"kind":"selection","id":"demo","title":"Demo"},"documentCount":0,"assetCount":0}"#,
            #"{"record":"future-one"}"#,
            #"{"record":"future-two"}"#,
            #"{"record":"future-three"}"#,
            #"{"record":"end","documentCount":0,"assetCount":0}"#,
        ]
        try Data(diagnosticLines.joined(separator: "\n").utf8).write(to: diagnosticURL)
        let diagnosticBoundedReader = FoundryVTTImportReader(limits: FoundryImportLimits(
            maximumRecordCount: 5,
            maximumDiagnosticCount: 1
        ))

        let package = try await diagnosticBoundedReader.read(from: diagnosticURL)

        #expect(package.diagnostics.count == 2)
        #expect(package.diagnostics.filter { $0.code == "unknown-bridge-record" }.isEmpty)
        #expect(package.diagnostics.contains { $0.code == "diagnostics-truncated" })
        #expect(package.diagnostics.contains { $0.code == "bridge-decoded" })

        let zeroDiagnosticReader = FoundryVTTImportReader(limits: FoundryImportLimits(
            maximumRecordCount: 5,
            maximumDiagnosticCount: 0
        ))
        let zeroDiagnosticPackage = try await zeroDiagnosticReader.read(from: diagnosticURL)
        #expect(zeroDiagnosticPackage.diagnostics.map(\.code) == ["bridge-decoded"])
    }

    @Test("Allows Base64 asset lines larger than the decoded bridge entry limit")
    func allowsEncodedBridgeAssetExpansion() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "expanded-asset.mrpgfoundry")
        let asset = Data(repeating: 0xab, count: 512)
        let lines = [
            #"{"record":"manifest","format":"masterrpg-foundry-bridge","version":1,"source":{"kind":"selection","id":"demo","title":"Demo"},"documentCount":0,"assetCount":1}"#,
            #"{"record":"asset","path":"assets/blob.bin","mediaType":"application/octet-stream","sha256":"\#(foundrySHA256(asset))","encoding":"base64","data":"\#(asset.base64EncodedString())"}"#,
            #"{"record":"end","documentCount":0,"assetCount":1}"#,
        ]
        let bridgeData = Data(lines.joined(separator: "\n").utf8)
        #expect(Data(lines[1].utf8).count > asset.count)
        try bridgeData.write(to: url)
        let reader = FoundryVTTImportReader(limits: FoundryImportLimits(maximumEntrySize: asset.count))

        let package = try await reader.read(from: url)
        let resource = try #require(package.resources.first)
        let reopened = try await reader.resourceData(for: resource, from: url)

        #expect(resource.byteCount == asset.count)
        #expect(reopened.data == asset)
    }

    @Test(
        "Rejects truncated or count-mismatched bridge exports",
        arguments: BridgeContractTestCase.invalidExports
    )
    func rejectsInvalidBridgeContract(testCase: BridgeContractTestCase) async throws {
        // Given
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "\(testCase.name).mrpgfoundry")
        try Data(testCase.lines.joined(separator: "\n").utf8).write(to: url)

        // When / Then
        await #expect(throws: FoundryImportError.self) {
            _ = try await FoundryVTTImportReader().read(from: url)
        }
    }

    @Test("Rejects bridge asset traversal")
    func rejectsBridgeTraversal() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "bad.mrpgfoundry")
        let image = Data([1])
        let lines = [
            #"{"record":"manifest","format":"masterrpg-foundry-bridge","version":1,"source":{"kind":"selection","id":"bad","title":"Bad"},"documentCount":0,"assetCount":1}"#,
            #"{"record":"asset","path":"../escape.png","mediaType":"image/png","sha256":"\#(foundrySHA256(image))","encoding":"base64","data":"\#(image.base64EncodedString())"}"#,
        ]
        try Data(lines.joined(separator: "\n").utf8).write(to: url)

        await #expect(throws: FoundryImportError.self) {
            _ = try await FoundryVTTImportReader().read(from: url)
        }
    }

    @Test("Reads Universal VTT geometry and lazily reopens its PNG")
    func readsUniversalVTT() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "dungeon.dd2vtt")
        let image = validPNGHeader()
        let json = ##"{"format":0.2,"resolution":{"map_origin":{"x":1,"y":2},"map_size":{"x":20,"y":10},"pixels_per_grid":50},"line_of_sight":[[{"x":0,"y":0},{"x":1,"y":1}]],"objects_line_of_sight":[[{"x":2,"y":2},{"x":3,"y":3}]],"portals":[{"position":{"x":4,"y":5},"bounds":[{"x":3,"y":5},{"x":5,"y":5}],"rotation":90,"closed":true,"freestanding":false}],"lights":[{"position":{"x":8,"y":9},"range":6,"intensity":0.5,"color":"#fff","shadows":true}],"image":"\##(image.base64EncodedString())"}"##
        try Data(json.utf8).write(to: url)

        let document = try await UniversalVTTReader().read(from: url)
        let reopened = try await FoundryVTTImportReader().resourceData(for: document.imageResource, from: url)

        #expect(document.resolution.pixelsPerGrid == 50)
        #expect(document.lineOfSight.first?.count == 2)
        #expect(document.objectsLineOfSight.first?.count == 2)
        #expect(document.portals.first?.isClosed == true)
        #expect(document.lights.first?.castsShadows == true)
        #expect(document.rawData["image"] == nil)
        #expect(reopened.data == image)
        #expect(try FoundryArtifactDetector().detect(at: url).kind == .universalVTT)
    }

    @Test("Hashes the complete Universal VTT payload independently from its image")
    func hashesUniversalVTTSourcePayload() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let image = validPNGHeader()
        let firstURL = directory.appending(path: "first.uvtt")
        let secondURL = directory.appending(path: "second.uvtt")
        let firstData = try universalVTTData(
            image: image,
            lineOfSight: [[
                ["x": 0, "y": 0],
                ["x": 1, "y": 1],
            ]]
        )
        let secondData = try universalVTTData(
            image: image,
            lineOfSight: [[
                ["x": 0, "y": 0],
                ["x": 2, "y": 2],
            ]]
        )
        try firstData.write(to: firstURL)
        try secondData.write(to: secondURL)

        let first = try await UniversalVTTReader().read(from: firstURL)
        let second = try await UniversalVTTReader().read(from: secondURL)

        #expect(first.sourceSHA256 == foundrySHA256(firstData))
        #expect(second.sourceSHA256 == foundrySHA256(secondData))
        #expect(first.sourceSHA256 != second.sourceSHA256)
        #expect(first.imageResource.sha256 == second.imageResource.sha256)
    }

    @Test("Preserves a Universal VTT WebP image type from a data URL")
    func readsUniversalVTTWebP() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "dungeon.json")
        let image = Data("RIFF\0\0\0\0WEBPVP8 ".utf8)
        let json = ##"{"resolution":{"map_origin":{"x":0,"y":0},"map_size":{"x":1,"y":1},"pixels_per_grid":100},"line_of_sight":[],"portals":[],"lights":[],"image":"data:image/webp;base64,\##(image.base64EncodedString())"}"##
        try Data(json.utf8).write(to: url)

        let document = try await UniversalVTTReader().read(from: url)
        let reopened = try await FoundryVTTImportReader().resourceData(for: document.imageResource, from: url)

        #expect(document.imageResource.logicalPath == "map.webp")
        #expect(reopened.data == image)
        #expect(try FoundryArtifactDetector().detect(at: url).kind == .universalVTT)
    }

    @Test("Rejects Universal VTT payloads without a supported image signature")
    func rejectsUnknownUniversalVTTImageSignatures() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        for (index, image) in [Data("not-an-image".utf8), Data([0x89, 0x50, 0x4e, 0x47])].enumerated() {
            let url = directory.appending(path: "invalid-image-\(index).uvtt")
            try universalVTTData(image: image).write(to: url)

            await #expect(throws: FoundryImportError.self) {
                _ = try await UniversalVTTReader().read(from: url)
            }
        }
    }

    @Test("Preflights base64 decoded length before creating decoded storage")
    func preflightsBase64DecodedLength() throws {
        let encoded = validPNGHeader().base64EncodedString()

        #expect(throws: FoundryImportError.fileTooLarge(8)) {
            _ = try FoundryBoundedBase64.decode(
                encoded,
                maximumDecodedByteCount: 7,
                invalidMessage: "invalid"
            )
        }
        #expect(try FoundryBoundedBase64.decode(
            encoded,
            maximumDecodedByteCount: 8,
            invalidMessage: "invalid"
        ) == validPNGHeader())
    }

    @Test("Rejects unbounded Universal VTT resolution values", arguments: ["0", "-1", "1e308"])
    func rejectsInvalidUniversalVTTResolution(pixelsPerGrid: String) async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "invalid-resolution.uvtt")
        let json = ##"{"resolution":{"map_origin":{"x":0,"y":0},"map_size":{"x":20,"y":10},"pixels_per_grid":\##(pixelsPerGrid)},"line_of_sight":[],"portals":[],"lights":[],"image":"\##(validPNGHeader().base64EncodedString())"}"##
        try Data(json.utf8).write(to: url)

        await #expect(throws: FoundryImportError.self) {
            _ = try await UniversalVTTReader().read(from: url)
        }
    }

    // CODE_AUDIT_26 §6.3: the file cap follows the image cap, not the 1 GiB archive cap.
    @Test("A Universal VTT file much larger than its image allows is refused before it is parsed")
    func rejectsOversizedUniversalVTTFile() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let limits = FoundryImportLimits(maximumArchiveSize: ByteUnit.gibibyte, maximumEntrySize: 3 * ByteUnit.mebibyte)
        let cap = UniversalVTTReader.maximumFileSize(for: limits)
        #expect(cap == 3 * ByteUnit.mebibyte / 3 * 4 + 8 * ByteUnit.mebibyte)
        #expect(cap < ByteUnit.gibibyte)

        let url = directory.appending(path: "padded.dd2vtt")
        let padding = String(repeating: "x", count: cap)
        let json = ##"{"resolution":{"map_origin":{"x":0,"y":0},"map_size":{"x":20,"y":10},"pixels_per_grid":50},"line_of_sight":[],"portals":[],"lights":[],"unused":"\##(padding)","image":"\##(validPNGHeader().base64EncodedString())"}"##
        try Data(json.utf8).write(to: url)

        await #expect(throws: FoundryImportError.self) {
            _ = try await UniversalVTTReader(limits: limits).read(from: url)
        }
    }

    @Test("Bounds geometry, portals, and lights with one aggregate element budget")
    func boundsUniversalVTTElements() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "too-many-elements.uvtt")
        let portals: [[String: Any]] = [
            ["position": ["x": 1, "y": 1]],
            ["position": ["x": 2, "y": 2]],
        ]
        let lights: [[String: Any]] = [
            ["position": ["x": 3, "y": 3]],
            ["position": ["x": 4, "y": 4]],
        ]
        try universalVTTData(image: validPNGHeader(), portals: portals, lights: lights).write(to: url)
        let reader = UniversalVTTReader(limits: FoundryImportLimits(maximumUniversalVTTElementCount: 3))

        await #expect(throws: FoundryImportError.tooManyUniversalVTTElements(4)) {
            _ = try await reader.read(from: url)
        }
    }

    @Test("A selected bare Foundry manifest cannot enumerate sibling files", arguments: [
        "system.json", "module.json", "world.json",
    ])
    func rejectsBareManifestSelection(filename: String) async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manifestURL = directory.appending(path: filename)
        try Data(#"{"id":"demo","title":"Demo"}"#.utf8).write(to: manifestURL)
        try Data(#"{"_id":"private","name":"Sibling"}"#.utf8).write(
            to: directory.appending(path: "actors.db")
        )

        await #expect(throws: FoundryImportError.bareManifestRequiresContainer(filename)) {
            _ = try await FoundryVTTImportReader().read(from: manifestURL)
        }
    }

    @Test("The rules reader also rejects a selected bare system manifest")
    func rulesReaderRejectsBareManifestSelection() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manifestURL = directory.appending(path: "system.json")
        try Data(#"{"id":"demo","title":"Demo","version":"1"}"#.utf8).write(to: manifestURL)

        await #expect(throws: FoundryImportError.bareManifestRequiresContainer("system.json")) {
            _ = try await FoundrySystemPackageReader().read(from: manifestURL)
        }
    }

    @Test("Applies an aggregate byte budget to package text resources")
    func boundsAggregateTextResources() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data(#"{"id":"demo","title":"Demo"}"#.utf8).write(
            to: directory.appending(path: "world.json")
        )
        try Data(#"{"_id":"hero","name":"Hero"}"#.utf8).write(
            to: directory.appending(path: "actors.db")
        )
        try Data(repeating: 0x61, count: 60).write(to: directory.appending(path: "LICENSE-A.txt"))
        try Data(repeating: 0x62, count: 60).write(to: directory.appending(path: "LICENSE-B.txt"))
        let reader = FoundryVTTImportReader(limits: FoundryImportLimits(maximumRuleDataSize: 100))

        await #expect(throws: FoundryImportError.fileTooLarge(120)) {
            _ = try await reader.read(from: directory)
        }
    }

    @Test("Artifact detection cooperatively observes cancellation")
    func detectorObservesCancellation() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data().write(to: directory.appending(path: "item.db"))
        let task = Task {
            while !Task.isCancelled { await Task.yield() }
            return try FoundryArtifactDetector().detect(at: directory)
        }
        task.cancel()

        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
    }

    @Test("A ZIP-packaged system reuses the archive parsed for the document decode when deriving its RuleRPG package")
    func systemPackageReusesTheParsedArchive() async throws {
        // Given: a ZIP-archived system (not a directory — every other system-package test in this
        // file/target reads from an extracted directory, where this reuse path never engages), so
        // this specifically exercises FoundryVTTImportReader.read(from:)'s
        // FoundrySystemPackageReader.read(reusingArchive:sourceSHA256:) fast path. See CODE_AUDIT_9 §7.3.
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manifest = #"""
        {
          "id": "ds4",
          "title": "Synthetic DS4",
          "version": "1.0.0",
          "packs": [
            { "name": "spells", "label": "Spells", "path": "./packs/spells", "type": "Item", "system": "ds4" }
          ]
        }
        """#
        let rule = #"""
        { "_id": "spell001", "name": "Spark", "type": "spell", "system": { "description": "" } }
        """#
        let table = FoundryLevelDBFixture.table(records: [
            FoundryLevelDBRecord(key: "!items!spell001", sequence: 1, operation: .value, value: Data(rule.utf8)),
        ])
        let zipURL = directory.appending(path: "ds4.zip")
        try makeFoundryZIPArchive(entries: [
            (path: "system.json", data: Data(manifest.utf8)),
            (path: "packs/spells/000005.ldb", data: table),
        ]).write(to: zipURL)

        // When
        let package = try await FoundryVTTImportReader().read(from: zipURL)

        // Then
        #expect(package.kind == .system)
        let rulePackage = try #require(package.rulePackage)
        #expect(rulePackage.manifest.id == "ds4")
        #expect(rulePackage.manifest.version == "1.0.0")
        #expect(rulePackage.rules.first?.name == "Spark")
        #expect(rulePackage.diagnostics.contains { $0.code == "rules-decoded" })
    }
}

struct BridgeContractTestCase: Sendable, CustomTestStringConvertible {
    let name: String
    let lines: [String]

    var testDescription: String { name }

    static let invalidExports = [
        Self(
            name: "missing-end",
            lines: [
                #"{"record":"manifest","format":"masterrpg-foundry-bridge","version":1,"source":{"kind":"selection","id":"bad","title":"Bad"},"documentCount":0,"assetCount":0}"#,
            ]
        ),
        Self(
            name: "manifest-document-mismatch",
            lines: [
                #"{"record":"manifest","format":"masterrpg-foundry-bridge","version":1,"source":{"kind":"selection","id":"bad","title":"Bad"},"documentCount":1,"assetCount":0}"#,
                #"{"record":"end","documentCount":1,"assetCount":0}"#,
            ]
        ),
        Self(
            name: "manifest-asset-mismatch",
            lines: [
                #"{"record":"manifest","format":"masterrpg-foundry-bridge","version":1,"source":{"kind":"selection","id":"bad","title":"Bad"},"documentCount":0,"assetCount":1}"#,
                #"{"record":"end","documentCount":0,"assetCount":1}"#,
            ]
        ),
        Self(
            name: "end-count-mismatch",
            lines: [
                #"{"record":"manifest","format":"masterrpg-foundry-bridge","version":1,"source":{"kind":"selection","id":"bad","title":"Bad"},"documentCount":0,"assetCount":0}"#,
                #"{"record":"end","documentCount":1,"assetCount":0}"#,
            ]
        ),
        Self(
            name: "missing-manifest-count",
            lines: [
                #"{"record":"manifest","format":"masterrpg-foundry-bridge","version":1,"source":{"kind":"selection","id":"bad","title":"Bad"},"documentCount":0}"#,
                #"{"record":"end","documentCount":0,"assetCount":0}"#,
            ]
        ),
        Self(
            name: "invalid-end-count",
            lines: [
                #"{"record":"manifest","format":"masterrpg-foundry-bridge","version":1,"source":{"kind":"selection","id":"bad","title":"Bad"},"documentCount":0,"assetCount":0}"#,
                #"{"record":"end","documentCount":0,"assetCount":-1}"#,
            ]
        ),
    ]
}

private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(
        path: "FoundryVTTImportReaderTests-\(UUID().uuidString)",
        directoryHint: .isDirectory
    )
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func writeDirectFoundryPackage(
    at directory: URL,
    collection: String,
    document: [String: Any]
) throws {
    try Data(#"{"id":"test-world","title":"Test World"}"#.utf8).write(
        to: directory.appending(path: "world.json")
    )
    let documentData = try JSONSerialization.data(withJSONObject: document, options: [.sortedKeys])
    try documentData.write(to: directory.appending(path: "\(collection).db"))
}

private func writeFoundryAsset(_ data: Data, path: String, in directory: URL) throws {
    let url = directory.appending(path: path)
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try data.write(to: url)
}

private func validPNGHeader() -> Data {
    Data([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])
}

private func universalVTTData(
    image: Data,
    lineOfSight: [[[String: Double]]] = [],
    portals: [[String: Any]] = [],
    lights: [[String: Any]] = []
) throws -> Data {
    let object: [String: Any] = [
        "resolution": [
            "map_origin": ["x": 0, "y": 0],
            "map_size": ["x": 10, "y": 10],
            "pixels_per_grid": 50,
        ],
        "line_of_sight": lineOfSight,
        "objects_line_of_sight": [],
        "portals": portals,
        "lights": lights,
        "image": image.base64EncodedString(),
    ]
    return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
}

private func manifestEdit(adding: [UInt64], deleting: [UInt64]) -> [UInt8] {
    var result: [UInt8] = []
    for file in adding {
        result += manifestVarint(7)
        result += manifestVarint(0)
        result += manifestVarint(file)
        result += manifestVarint(1)
        result += manifestVarint(0)
        result += manifestVarint(0)
    }
    for file in deleting {
        result += manifestVarint(6)
        result += manifestVarint(0)
        result += manifestVarint(file)
    }
    return result
}

private func manifestRecord(_ payload: [UInt8]) -> [UInt8] {
    let type: UInt8 = 1
    let checksum = FoundryCRC32C.maskedChecksum([type] + payload)
    return [
        UInt8(truncatingIfNeeded: checksum),
        UInt8(truncatingIfNeeded: checksum >> 8),
        UInt8(truncatingIfNeeded: checksum >> 16),
        UInt8(truncatingIfNeeded: checksum >> 24),
        UInt8(truncatingIfNeeded: payload.count),
        UInt8(truncatingIfNeeded: payload.count >> 8),
        type,
    ] + payload
}

private func manifestVarint(_ value: UInt64) -> [UInt8] {
    var value = value
    var result: [UInt8] = []
    while value >= 0x80 {
        result.append(UInt8(value & 0x7f) | 0x80)
        value >>= 7
    }
    result.append(UInt8(value))
    return result
}

/// A minimal stored-entries-only ZIP writer, just enough to exercise the ZIP-archive branch of
/// `FoundryVTTImportReader.read(from:)` (every other system-package fixture in this target reads
/// from an extracted directory instead). Mirrors `FoundryZIPArchiveTests.swift`'s own fixture
/// writer; kept separate since that one is file-private to its own file.
private func makeFoundryZIPArchive(entries: [(path: String, data: Data)]) -> Data {
    var localRecords = Data()
    var centralDirectory = Data()

    for entry in entries {
        let pathData = Data(entry.path.utf8)
        let checksum = foundryZIPFixtureCRC32(of: entry.data)
        let localOffset = UInt32(localRecords.count)

        localRecords.appendFoundryZIPLittleEndian(UInt32(0x0403_4B50))
        localRecords.appendFoundryZIPLittleEndian(UInt16(20))
        localRecords.appendFoundryZIPLittleEndian(UInt16(0x0800))
        localRecords.appendFoundryZIPLittleEndian(UInt16(0))
        localRecords.appendFoundryZIPLittleEndian(UInt16(0))
        localRecords.appendFoundryZIPLittleEndian(UInt16(0))
        localRecords.appendFoundryZIPLittleEndian(checksum)
        localRecords.appendFoundryZIPLittleEndian(UInt32(entry.data.count))
        localRecords.appendFoundryZIPLittleEndian(UInt32(entry.data.count))
        localRecords.appendFoundryZIPLittleEndian(UInt16(pathData.count))
        localRecords.appendFoundryZIPLittleEndian(UInt16(0))
        localRecords.append(pathData)
        localRecords.append(entry.data)

        centralDirectory.appendFoundryZIPLittleEndian(UInt32(0x0201_4B50))
        centralDirectory.appendFoundryZIPLittleEndian(UInt16(20))
        centralDirectory.appendFoundryZIPLittleEndian(UInt16(20))
        centralDirectory.appendFoundryZIPLittleEndian(UInt16(0x0800))
        centralDirectory.appendFoundryZIPLittleEndian(UInt16(0))
        centralDirectory.appendFoundryZIPLittleEndian(UInt16(0))
        centralDirectory.appendFoundryZIPLittleEndian(UInt16(0))
        centralDirectory.appendFoundryZIPLittleEndian(checksum)
        centralDirectory.appendFoundryZIPLittleEndian(UInt32(entry.data.count))
        centralDirectory.appendFoundryZIPLittleEndian(UInt32(entry.data.count))
        centralDirectory.appendFoundryZIPLittleEndian(UInt16(pathData.count))
        centralDirectory.appendFoundryZIPLittleEndian(UInt16(0))
        centralDirectory.appendFoundryZIPLittleEndian(UInt16(0))
        centralDirectory.appendFoundryZIPLittleEndian(UInt16(0))
        centralDirectory.appendFoundryZIPLittleEndian(UInt16(0))
        centralDirectory.appendFoundryZIPLittleEndian(UInt32(0))
        centralDirectory.appendFoundryZIPLittleEndian(localOffset)
        centralDirectory.append(pathData)
    }

    var archive = localRecords
    let centralDirectoryOffset = UInt32(archive.count)
    archive.append(centralDirectory)
    archive.appendFoundryZIPLittleEndian(UInt32(0x0605_4B50))
    archive.appendFoundryZIPLittleEndian(UInt16(0))
    archive.appendFoundryZIPLittleEndian(UInt16(0))
    archive.appendFoundryZIPLittleEndian(UInt16(entries.count))
    archive.appendFoundryZIPLittleEndian(UInt16(entries.count))
    archive.appendFoundryZIPLittleEndian(UInt32(centralDirectory.count))
    archive.appendFoundryZIPLittleEndian(centralDirectoryOffset)
    archive.appendFoundryZIPLittleEndian(UInt16(0))
    return archive
}

private func foundryZIPFixtureCRC32(of data: Data) -> UInt32 {
    var checksum = UInt32.max
    for byte in data {
        checksum ^= UInt32(byte)
        for _ in 0..<8 {
            let mask = UInt32(bitPattern: -Int32(checksum & 1))
            checksum = checksum >> 1 ^ (0xEDB8_8320 & mask)
        }
    }
    return checksum ^ UInt32.max
}

private extension Data {
    mutating func appendFoundryZIPLittleEndian(_ value: UInt16) {
        append(UInt8(truncatingIfNeeded: value))
        append(UInt8(truncatingIfNeeded: value >> 8))
    }

    mutating func appendFoundryZIPLittleEndian(_ value: UInt32) {
        append(UInt8(truncatingIfNeeded: value))
        append(UInt8(truncatingIfNeeded: value >> 8))
        append(UInt8(truncatingIfNeeded: value >> 16))
        append(UInt8(truncatingIfNeeded: value >> 24))
    }
}
