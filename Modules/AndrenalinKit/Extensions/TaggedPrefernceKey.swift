// @copyright André Trettin

import SwiftUI

public struct TaggedKey<Value, Tag>: PreferenceKey {
    public static var defaultValue: Value? { nil }
    public static func reduce(value: inout Value?, nextValue: () -> Value?) {
        value = value ?? nextValue()
    }
}
