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
        set {
            if let textValue = newValue as? String, let data = textValue.data(using: .utf8), let value = try? JSONDecoder().decode(LWWRegister<String, T>.self, from: data) {
                _crdtValue = value
            } else {
                _crdtValue.value = newValue
            }
        }
    }

    private static func converter(initialValue: String, defaultValue: T) -> LWWRegister<String, T> {
        if let data = initialValue.data(using: .utf8), let value = try? JSONDecoder().decode(LWWRegister<String, T>.self, from: data) {
            return value
        }
        return LWWRegister(defaultValue, actorID: UUID().uuidString)
    }

    public var projectedValue: Self {
        self
    }

    public var rawValue: String {
        guard let data = try? JSONEncoder().encode(_crdtValue), let text = String(data: data, encoding: .utf8) else { return "" }
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
