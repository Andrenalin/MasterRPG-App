// @copyright André Trettin

import CryptoKit
import Foundation
import Synchronization

// The JSON value tree and its depth-guarded coding, split out of FoundryRuleModels.swift. See CODE_AUDIT_29 §9.9.

/// A lossless, concurrency-safe representation of a value stored in a Foundry document.
///
/// `RuleRPG` can persist or map these values without depending on a specific Foundry game
/// system's Swift types.
public enum FoundryJSONValue: Codable, Equatable, Sendable {
    case object([String: FoundryJSONValue])
    case array([FoundryJSONValue])
    case string(String)
    case integer(Int64)
    case unsignedInteger(UInt64)
    case number(Double)
    case bool(Bool)
    case null

    /// A ~200 KB payload of ~100,000 nested arrays (`[[[[[…]]]]]`) — well under any
    /// per-entry size cap — would otherwise recurse one native stack frame per level
    /// during decode and crash the process via stack overflow. See CODE_AUDIT §5.9.
    static let maximumNestingDepth = 128

    /// Longest coding path accepted when no depth counter is installed.
    static let maximumUncountedCodingPathLength = 2 * maximumNestingDepth

    public init(from decoder: any Decoder) throws {
        let depthCounter = decoder.userInfo[.masterRPGFoundryJSONDepth] as? FoundryJSONDepthCounter
        depthCounter?.depth += 1
        defer { depthCounter?.depth -= 1 }
        if let depthCounter {
            if depthCounter.depth > Self.maximumNestingDepth {
                throw DecodingError.dataCorrupted(DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Foundry JSON nesting exceeds the maximum supported depth of \(Self.maximumNestingDepth)."
                ))
            }
        } else if decoder.codingPath.count > Self.maximumUncountedCodingPathLength {
            // Decodes from CoreData, the network and `.gmz` imports install no counter, so the
            // guard lives here: every nesting level adds one coding-path element. The limit
            // leaves room for the enclosing model's own path. See CODE_AUDIT_20 §6.3.
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: [],
                debugDescription: "Foundry JSON nesting exceeds the maximum supported depth."
            ))
        }

        if decoder.userInfo[.masterRPGFoundrySourceJSON] as? Bool != true,
           let taggedContainer = try? decoder.container(keyedBy: FoundryJSONCodingKey.self),
           Set(taggedContainer.allKeys.map(\.stringValue)) == FoundryJSONCodingKey.numericKeys,
           let numericType = try? taggedContainer.decode(
               FoundryJSONNumericType.self,
               forKey: .numericType
           ) {
            switch numericType {
            case .integer:
                self = .integer(try taggedContainer.decode(Int64.self, forKey: .numericValue))
            case .unsignedInteger:
                self = .unsignedInteger(try taggedContainer.decode(UInt64.self, forKey: .numericValue))
            case .number:
                self = .number(try taggedContainer.decode(Double.self, forKey: .numericValue))
            }
            return
        }

        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int64.self) {
            self = .integer(value)
        } else if let value = try? container.decode(UInt64.self) {
            self = .unsignedInteger(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([FoundryJSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: FoundryJSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported Foundry JSON value")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        switch self {
        case .object(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .array(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .string(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .integer(let value):
            var container = encoder.container(keyedBy: FoundryJSONCodingKey.self)
            try container.encode(FoundryJSONNumericType.integer, forKey: .numericType)
            try container.encode(value, forKey: .numericValue)
        case .unsignedInteger(let value):
            var container = encoder.container(keyedBy: FoundryJSONCodingKey.self)
            try container.encode(FoundryJSONNumericType.unsignedInteger, forKey: .numericType)
            try container.encode(value, forKey: .numericValue)
        case .number(let value):
            var container = encoder.container(keyedBy: FoundryJSONCodingKey.self)
            try container.encode(FoundryJSONNumericType.number, forKey: .numericType)
            try container.encode(value, forKey: .numericValue)
        case .bool(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .null:
            var container = encoder.singleValueContainer()
            try container.encodeNil()
        }
    }

    public var objectValue: [String: FoundryJSONValue]? {
        guard case .object(let value) = self else { return nil }
        return value
    }

    public var arrayValue: [FoundryJSONValue]? {
        guard case .array(let value) = self else { return nil }
        return value
    }

    public var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    public var integerValue: Int64? {
        switch self {
        case .integer(let value): value
        case .unsignedInteger(let value): Int64(exactly: value)
        case .number(let value) where value.rounded() == value: Int64(exactly: value)
        default: nil
        }
    }

    public var boolValue: Bool? {
        guard case .bool(let value) = self else { return nil }
        return value
    }

    public subscript(key: String) -> FoundryJSONValue? {
        objectValue?[key]
    }

    public func value(at path: String) -> FoundryJSONValue? {
        value(at: path.split(separator: ".").map(String.init))
    }

    public func value(at path: [String]) -> FoundryJSONValue? {
        path.reduce(Optional(self)) { value, component in
            value?[component]
        }
    }
}

extension CodingUserInfoKey {
    static let masterRPGFoundrySourceJSON = Self(
        rawValue: BundleIds.app("decodeFoundrySourceJSON")
    )!
    static let masterRPGFoundryJSONDepth = Self(
        rawValue: BundleIds.app("decodeFoundryJSONDepth")
    )!
}

/// Recursion-depth counter threaded through a `JSONDecoder`'s `userInfo` so
/// `FoundryJSONValue.init(from:)` can bound its own nesting. Codable hands each
/// nested array/object element its own fresh `Decoder`/`init(from:)` call, so a
/// plain local variable can't observe depth across those calls — `userInfo` is
/// the only channel threaded through the whole recursive decode, and it needs a
/// reference type since `Decoder` only exposes it for reading.
// Checked `Sendable`: the depth lives in a `Mutex` instead of an unsynchronized `var`
// justified only by how it is used. See CODE_AUDIT §3.5 and CODE_AUDIT_18 §3.18.
final class FoundryJSONDepthCounter: Sendable {
    private let storage = Mutex(0)

    var depth: Int {
        get { storage.withLock { $0 } }
        set { storage.withLock { $0 = newValue } }
    }
}

private enum FoundryJSONNumericType: String, Codable {
    case integer
    case unsignedInteger
    case number
}

private struct FoundryJSONCodingKey: CodingKey, Hashable {
    static let numericType = Self(stringValue: "__masterRPGFoundryNumericType")
    static let numericValue = Self(stringValue: "__masterRPGFoundryNumericValue")
    static let numericKeys = Set([numericType.stringValue, numericValue.stringValue])

    let stringValue: String
    let intValue: Int?

    init(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}
