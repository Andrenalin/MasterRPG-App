// @copyright André Trettin

import Foundation

@propertyWrapper
public struct IgnoreEquatable<Wrapped>: Equatable {
    public var wrappedValue: Wrapped

    public static func == (
        lhs: IgnoreEquatable<Wrapped>,
        rhs: IgnoreEquatable<Wrapped>
    ) -> Bool {
        true
    }

    public init(wrappedValue: Wrapped) {
        self.wrappedValue = wrappedValue
    }
}

@propertyWrapper
public struct IgnoreHashable<Wrapped>: Hashable {
    @IgnoreEquatable public var wrappedValue: Wrapped

    public func hash(into hasher: inout Hasher) {}

    public init(wrappedValue: Wrapped) {
        self.wrappedValue = wrappedValue
    }
}
