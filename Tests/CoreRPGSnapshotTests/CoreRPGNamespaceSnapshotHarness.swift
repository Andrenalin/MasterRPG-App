// @copyright André Trettin

import SwiftUI

@MainActor
struct CoreRPGNamespaceSnapshotHarness<Content: View>: View {
    @Namespace private var namespace

    private let content: (Namespace.ID) -> Content

    init(@ViewBuilder content: @escaping (Namespace.ID) -> Content) {
        self.content = content
    }

    var body: some View {
        content(namespace)
    }
}
