// @copyright André Trettin

import Foundation
import Testing

@testable import CoreRPG

@Suite("Foundry rule interchange models")
struct FoundryRuleModelsTests {
    @Test func jsonValueRoundTripsNullIntegerAndNumberSeparately() throws {
        let value = FoundryJSONValue.object([
            "null": .null,
            "integer": .integer(42),
            "smallUnsigned": .unsignedInteger(1),
            "unsigned": .unsignedInteger(UInt64.max),
            "integralNumber": .number(4.0),
            "number": .number(4.25),
            "boolean": .bool(true),
            "array": .array([.string("rule"), .integer(7)])
        ])

        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(FoundryJSONValue.self, from: data)

        #expect(decoded == value)
        #expect(decoded.value(at: "integer")?.integerValue == 42)
        #expect(decoded.value(at: "smallUnsigned") == .unsignedInteger(1))
        #expect(decoded.value(at: "unsigned") == .unsignedInteger(UInt64.max))
        #expect(decoded.value(at: "integralNumber") == .number(4.0))
        #expect(decoded.value(at: "array")?.arrayValue?.count == 2)
    }

    @Test func canonicalRuleIdentityIsStableAndUsesVersionEight() {
        let key = "foundry://system/ds4/pack/talents/Item/11ZOcPcDIigrXvww"

        let first = FoundryRuleIdentity.uuid(for: key)
        let second = FoundryRuleIdentity.uuid(for: key)
        let other = FoundryRuleIdentity.uuid(for: key + "x")

        #expect(first == second)
        #expect(first != other)
        #expect(first.uuidString.split(separator: "-")[2].first == "8")
    }

    @Test func sourceJSONDoesNotInterpretPersistenceNumericTags() throws {
        let data = Data(#"{"__masterRPGFoundryNumericType":"integer","__masterRPGFoundryNumericValue":7}"#.utf8)
        let decoder = JSONDecoder()
        decoder.userInfo[.masterRPGFoundrySourceJSON] = true

        let value = try decoder.decode(FoundryJSONValue.self, from: data)

        #expect(value == .object([
            "__masterRPGFoundryNumericType": .string("integer"),
            "__masterRPGFoundryNumericValue": .integer(7),
        ]))
    }

    @Test func packageCodableRoundTripKeepsRawTemplateAndStableRuleID() throws {
        let manifestRaw = FoundryJSONValue.object(["id": .string("ds4")])
        let manifest = FoundrySystemManifest(
            id: "ds4",
            title: "Dungeonslayers 4",
            description: nil,
            version: "2.0.5",
            compatibility: .init(minimum: "12.331", verified: "12", maximum: nil),
            packs: [],
            rawData: manifestRaw
        )
        let package = FoundryRulePackage(
            sourceSHA256: String(repeating: "a", count: 64),
            manifest: manifest,
            manifestPath: "ds4/system.json",
            templatePath: "ds4/template.json",
            templateData: .object(["Actor": .object([:])]),
            schemas: [],
            compendiums: [],
            localizations: [],
            assetPaths: ["systems/ds4/icons/spell.webp"],
            resources: [
                .init(
                    logicalPath: "systems/ds4/icons/spell.webp",
                    packagePath: "ds4/icons/spell.webp",
                    location: .packaged,
                    byteCount: 4,
                    sha256: String(repeating: "b", count: 64)
                )
            ],
            licensePaths: ["ds4/LICENSE.md"],
            licenseDocuments: [.init(path: "ds4/LICENSE.md", content: "License")],
            diagnostics: []
        )

        let data = try JSONEncoder().encode(package)
        let decoded = try JSONDecoder().decode(FoundryRulePackage.self, from: data)

        #expect(decoded == package)
        #expect(decoded.formatVersion == FoundryRulePackage.currentFormatVersion)
    }
}
