// @copyright André Trettin

import SwiftUI

@MainActor
struct CoreRPGFocusSnapshotHarness<Value: Hashable, Content: View>: View {
    @FocusState private var focusedValue: Value?

    private let content: (FocusState<Value?>.Binding) -> Content

    init(
        _: Value.Type,
        @ViewBuilder content: @escaping (FocusState<Value?>.Binding) -> Content
    ) {
        self.content = content
    }

    var body: some View {
        content($focusedValue)
    }
}
