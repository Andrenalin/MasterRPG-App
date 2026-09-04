// @copyright André Trettin

import Foundation

@propertyWrapper
public struct CRDT<T: Codable> {
    public var _crdtValue: LWWRegister<String, T>

    public init(wrappedValue initialValue: T) {
        if let textValue = initialValue as? String {
            _crdtValue = Self.converter(initialValue: textValue, defaultValue: initialValue)
        } else {
            _crdtValue = LWWRegister(initialValue, actorID: UUID().uuidString)
        }
    }

    public init(string: String, defaultValue: T) {
        _crdtValue = Self.converter(initialValue: string, defaultValue: defaultValue)
    }

    public init(crdtValue: LWWRegister<String, T>) {
        _crdtValue = crdtValue
    }

    public var wrappedValue: T {
        get { _crdtValue.value }
        set { _crdtValue.value = newValue }
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
    }

    private static func converter(initialValue: String, defaultValue: T) -> LWWRegister<String, T> {
        if let data = initialValue.data(using: .utf8), let value = try? JSONCoding.decoder.decode(LWWRegister<String, T>.self, from: data) {
            return value
        }
        return LWWRegister(defaultValue, actorID: UUID().uuidString)
    }

    public var projectedValue: Self {
        self
    }

    public var rawValue: String {
        guard let data = try? JSONCoding.encoder.encode(_crdtValue), let text = String(data: data, encoding: .utf8) else { return "" }
        return text
    }

    public func merged(other: Self) -> Self {
        CRDT(crdtValue: _crdtValue.merged(with: other._crdtValue))
    }
}

extension CRDT: Equatable where T: Equatable {}
extension CRDT: Hashable where T: Hashable {}
extension CRDT: Codable where T: Codable {}
extension CRDT: Sendable where T: Sendable {}
