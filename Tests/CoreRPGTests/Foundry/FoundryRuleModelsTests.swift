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

    /// CODE_AUDIT §5.9: a small, deeply-nested JSON payload previously recursed one
    /// native stack frame per nesting level with no depth guard — a stack-overflow
    /// crash, not a catchable error. Every real import entry point injects a depth
    /// counter into `userInfo`; this mirrors that configuration.
    private func decoderWithDepthGuard() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.userInfo[.masterRPGFoundrySourceJSON] = true
        decoder.userInfo[.masterRPGFoundryJSONDepth] = FoundryJSONDepthCounter()
        return decoder
    }

    private func nestedArrayJSON(depth: Int) -> Data {
        Data((String(repeating: "[", count: depth) + "0" + String(repeating: "]", count: depth)).utf8)
    }

    @Test func deeplyNestedArraysWithinTheDepthLimitDecodeNormally() throws {
        let depth = FoundryJSONValue.maximumNestingDepth - 1
        let value = try decoderWithDepthGuard().decode(FoundryJSONValue.self, from: nestedArrayJSON(depth: depth))

        var unwrapped = value
        for _ in 0..<depth {
            unwrapped = try #require(unwrapped.arrayValue?.first)
        }
        #expect(unwrapped == .integer(0))
    }

    @Test func arraysPastTheDepthLimitAreRejectedRatherThanCrashing() throws {
        let payload = nestedArrayJSON(depth: 100_000)

        #expect(throws: DecodingError.self) {
            _ = try decoderWithDepthGuard().decode(FoundryJSONValue.self, from: payload)
        }
    }

    @Test func objectsPastTheDepthLimitAreRejectedRatherThanCrashing() throws {
        let payload = Data(
            (String(repeating: #"{"a":"#, count: 100_000) + "0" + String(repeating: "}", count: 100_000)).utf8
        )

        #expect(throws: DecodingError.self) {
            _ = try decoderWithDepthGuard().decode(FoundryJSONValue.self, from: payload)
        }
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
