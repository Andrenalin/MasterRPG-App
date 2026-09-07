// @copyright André Trettin

import SwiftUI

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
