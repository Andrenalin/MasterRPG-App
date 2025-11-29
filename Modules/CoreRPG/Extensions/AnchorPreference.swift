// @copyright André Trettin

import SwiftUI

public struct AnchorKey<A>: PreferenceKey {
    public typealias Value = Anchor<A>?
    public static var defaultValue: Value { nil }

    public static func reduce(value: inout Value, nextValue: () -> Value) {
        value = nextValue()
    }
}

public extension View {
    func overlayWithAnchor<A, V: View>(value: Anchor<A>.Source, transform: @escaping (Anchor<A>) -> V) -> some View {
        let key = TaggedKey<Anchor<A>, Void>.self

        return anchorPreference(key: key, value: value, transform: { $0 })
            .overlayPreferenceValue(key) { anchor in
                transform(anchor!)
            }
            .preference(key: key, value: nil)
    }
}
