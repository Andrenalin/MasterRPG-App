// @copyright André Trettin

import SwiftUI

public struct MenuTV<Label: View, Content: View>: View {
    public let content: () -> Content
    public let label: () -> Label
    public let primaryAction: (() -> Void)?

    public init(@ViewBuilder content: @escaping () -> Content, @ViewBuilder label: @escaping () -> Label, primaryAction: (() -> Void)? = nil) {
        self.content = content
        self.label = label
        self.primaryAction = primaryAction
    }

    public var body: some View {
#if os(tvOS)
        HStack(spacing: 16) {
            content()
        }
#else
        if let primaryAction {
            Menu(content: content, label: label, primaryAction: primaryAction)
        } else {
            Menu(content: content, label: label)
        }
#endif
    }
}

#Preview("Menu") {
    MenuTV {
        Button(action: {}) {
            Text(verbatim: "Edit")
        }
        Button(action: {}) {
            Text(verbatim: "Duplicate")
        }
    } label: {
        Label {
            Text(verbatim: "Actions")
        } icon: {
            Image(systemName: "ellipsis.circle")
        }
    }
    .padding()
}
