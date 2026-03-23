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

//@propertyWrapper
//public struct CRDT<T: Codable> {
//    public var _crdtValue: LWWRegister<String, T>
//
//    // Cache to avoid redundant JSON decoding
//    private final class Cache: @unchecked Sendable {
//        private var cachedString: String?
//        private var cachedRegister: LWWRegister<String, T>?
//        private let lock = NSLock()
//
//        func get(forString string: String, compute: () -> LWWRegister<String, T>) -> LWWRegister<String, T> {
//            lock.lock()
//            defer { lock.unlock() }
//
//            // If we've already decoded this exact string, return cached result
//            if let cachedString, cachedString == string, let cachedRegister {
//                return cachedRegister
//            }
//            // Otherwise compute, cache, and return
//            let result = compute()
//            cachedString = string
//            cachedRegister = result
//            return result
//        }
//
//        func invalidate() {
//            lock.lock()
//            defer { lock.unlock() }
//            cachedString = nil
//            cachedRegister = nil
//        }
//    }
//
//    private let cache: Cache
//
//    public init(wrappedValue initialValue: T) {
//        cache = Cache()
//        if let textValue = initialValue as? String {
//            _crdtValue = Self.converter(initialValue: textValue, defaultValue: initialValue, cache: cache)
//        } else {
//            _crdtValue = LWWRegister(initialValue, actorID: UUID().uuidString)
//        }
//    }
//
//    public init(string: String, defaultValue: T) {
//        cache = Cache()
//        _crdtValue = Self.converter(initialValue: string, defaultValue: defaultValue, cache: cache)
//    }
//
//    public init(crdtValue: LWWRegister<String, T>) {
//        cache = Cache()
//        _crdtValue = crdtValue
//    }
//
//    public var wrappedValue: T {
//        get { _crdtValue.value }
//        set {
//            cache.invalidate()
//            if let textValue = newValue as? String, let data = textValue.data(using: .utf8), let value = try? // DecoderPool.shared.getDecoder().decode(LWWRegister<String, T>.self, from: data) {
//                JSONDecoder().decode(LWWRegister<String, T>.self, from: data) {
//                _crdtValue = value
//            } else {
//                _crdtValue.value = newValue
//            }
//        }
//    }
//
//    private static func converter(initialValue: String, defaultValue: T, cache: Cache) -> LWWRegister<String, T> {
//        cache.get(forString: initialValue) {
//            if let data = initialValue.data(using: .utf8), let value = try?  //DecoderPool.shared.getDecoder().decode(LWWRegister<String, T>.self, from: data) {
//                JSONDecoder().decode(LWWRegister<String, T>.self, from: data) {
//                return value
//            }
//            return LWWRegister(defaultValue, actorID: UUID().uuidString)
//        }
//    }
//
//    public var projectedValue: Self {
//        self
//    }
//
//    public var rawValue: String {
//        guard let data = try? JSONEncoder().encode(_crdtValue), let text = String(data: data, encoding: .utf8) else { return "" }
//        return text
//    }
//
//    public func merged(other: Self) -> Self {
//        CRDT(crdtValue: _crdtValue.merged(with: other._crdtValue))
//    }
//}

//extension CRDT: Equatable where T: Equatable {
//    public static func == (lhs: CRDT<T>, rhs: CRDT<T>) -> Bool {
//        lhs._crdtValue == rhs._crdtValue
//    }
//}
//
//extension CRDT: Hashable where T: Hashable {
//    public func hash(into hasher: inout Hasher) {
//        hasher.combine(_crdtValue)
//    }
//}
//
//extension CRDT: Codable where T: Codable {
//    public init(from decoder: Decoder) throws {
//        let container = try decoder.singleValueContainer()
//        _crdtValue = try container.decode(LWWRegister<String, T>.self)
//        //cache = Cache()
//    }
//
//    public func encode(to encoder: Encoder) throws {
//        var container = encoder.singleValueContainer()
//        try container.encode(_crdtValue)
//    }
//}

extension CRDT: Equatable where T: Equatable {}
extension CRDT: Hashable where T: Hashable {}
extension CRDT: Codable where T: Codable {}
extension CRDT: Sendable where T: Sendable {}
