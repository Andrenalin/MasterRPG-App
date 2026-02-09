// @copyright André Trettin

import Foundation

@propertyWrapper
public struct CRDTDataUpdate<Value: Equatable> {
    private var _value: Value

    @CRDT public private(set) var update: UUID

    public init(wrappedValue initialValue: Value, update: CRDT<UUID> = CRDT(wrappedValue: UUID())) {
        _value = initialValue
        _update = update
    }

    public var wrappedValue: Value {
        get { _value }
        set {
            if _value != newValue {
                _value = newValue
                update = UUID()
            }
        }
    }

    public var projectedValue: Self {
        self
    }

    public func merged(other: Self) -> Self {
        let newUpdate = $update.merged(other: other.$update)
        let newValue = newUpdate.wrappedValue == update ? _value : other._value
        return CRDTDataUpdate(wrappedValue: newValue, update: newUpdate)
    }
}

extension CRDTDataUpdate: Equatable where Value: Equatable {}
extension CRDTDataUpdate: Hashable where Value: Hashable {}
extension CRDTDataUpdate: Codable where Value: Codable {}
extension CRDTDataUpdate: Sendable where Value: Sendable {}
