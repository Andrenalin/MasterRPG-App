// @copyright André Trettin

import Foundation
import os.log

@propertyWrapper
public struct CRDT<T: Codable> {
    public var _crdtValue: LWWRegister<String, T>

    /// The stored text of a register that is serialized but that this build cannot read as a
    /// `T`, typically written by a newer build (a case this build does not know). The register
    /// then holds the module default stamped at the epoch, so any real value wins a merge over
    /// it, and `rawValue` returns this text until a local edit replaces the value, so saving does
    /// not overwrite what a newer build wrote. See CODE_AUDIT_28 §5.4.
    public private(set) var unreadableRawValue: String?

    public init(wrappedValue initialValue: T) {
        if let textValue = initialValue as? String {
            (_crdtValue, unreadableRawValue) = Self.parse(string: textValue, defaultValue: initialValue)
        } else {
            _crdtValue = LWWRegister(initialValue, actorID: UUID().uuidString)
        }
    }

    public init(string: String, defaultValue: T) {
        (_crdtValue, unreadableRawValue) = Self.parse(string: string, defaultValue: defaultValue)
    }

    /// The register stored in `string`; for text that is not a register of this type the default:
    /// plain text of an older build (a name, a comma separated tag list) gets a fresh register
    /// (the migration path), a register this build cannot read gets an epoch-stamped one and its
    /// text is returned to be kept.
    private static func parse(string: String, defaultValue: T) -> (LWWRegister<String, T>, String?) {
        if let data = string.data(using: .utf8),
           let value = try? JSONCoding.decoder.decode(LWWRegister<String, T>.self, from: data) {
            return (value, nil)
        }
        if looksLikeSerializedRegister(string) {
            Logger.coreDataController.error("CRDT: kept a stored register this build cannot read as \(String(describing: T.self), privacy: .public)")
            return (LWWRegister(defaultValue, actorID: LocalActorId.value, timestamp: 0), string)
        }
        return (LWWRegister(defaultValue, actorID: UUID().uuidString), nil)
    }

    public init(crdtValue: LWWRegister<String, T>) {
        _crdtValue = crdtValue
    }

    /// Whether `string` is the serialized form of some register (any value type), as opposed to
    /// plain text: a JSON object with the register's `_storage` and `selfId` members.
    private static func looksLikeSerializedRegister(_ string: String) -> Bool {
        guard string.hasPrefix("{"), let data = string.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return object["_storage"] != nil && object["selfId"] != nil
    }

    /// The register stored in `string`, `nil` when `string` is not a serialized register of this
    /// type. Unlike `init(string:defaultValue:)` it never invents a fresh register stamped now,
    /// which would win a merge over the real one: the caller decides what an unreadable value means.
    public init?(validating string: String) {
        guard let data = string.data(using: .utf8),
              let value = try? JSONCoding.decoder.decode(LWWRegister<String, T>.self, from: data) else {
            return nil
        }
        _crdtValue = value
    }

    public var wrappedValue: T {
        get { _crdtValue.value }
        set {
            _crdtValue.value = newValue
            unreadableRawValue = nil
        }
    }

    /// Explicitly restores the register's full serialized state (actor ID,
    /// timestamp, value) from its `rawValue` JSON form — e.g. re-hydrating a
    /// previously exported `CRDT`. Distinct from the plain setter above, which
    /// always performs a normal, tracked LWW value update: this is a
    /// deserialize, not a user edit, so it replaces the register wholesale
    /// (mirroring `init(string:defaultValue:)`) instead of going through LWW
    /// history. Previously the plain setter itself special-cased this when
    /// `T == String` and the new value happened to parse as the register's own
    /// JSON schema — silently discarding provenance on what looked like an
    /// ordinary text edit. No-op if `string` isn't valid serialized register
    /// JSON. See CODE_AUDIT_9 §5.6.
    public mutating func restore(from string: String) {
        guard let data = string.data(using: .utf8),
              let value = try? JSONCoding.decoder.decode(LWWRegister<String, T>.self, from: data) else {
            return
        }
        _crdtValue = value
        unreadableRawValue = nil
    }

    public var projectedValue: Self {
        self
    }

    public var rawValue: String {
        if let unreadableRawValue { return unreadableRawValue }
        guard let data = try? JSONCoding.encoder.encode(_crdtValue), let text = String(data: data, encoding: .utf8) else {
            assertionFailure("CRDT value failed to encode; persisting an empty string would erase it")
            return ""
        }
        return text
    }

    public func merged(other: Self) -> Self {
        // An unreadable register carries no value: the readable side is the result, and when
        // neither is readable this side keeps its text.
        if other.unreadableRawValue != nil { return self }
        if unreadableRawValue != nil { return other }
        return CRDT(crdtValue: _crdtValue.merged(with: other._crdtValue))
    }
}

extension CRDT: Equatable where T: Equatable {}
extension CRDT: Hashable where T: Hashable {}
extension CRDT: Codable where T: Codable {
    private enum CodingKeys: String, CodingKey {
        case _crdtValue
    }
}
extension CRDT: Sendable where T: Sendable {}
