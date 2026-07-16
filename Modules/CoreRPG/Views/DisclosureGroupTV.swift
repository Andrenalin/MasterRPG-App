// @copyright André Trettin

import SwiftUI

public struct DisclosureGroupTV<Label: View, Content: View>: View {
    @Binding public var isExpanded: Bool
    public let content: () -> Content
    public let label: () -> Label
    private let hasExpanded: Bool

    public init(@ViewBuilder content: @escaping () -> Content, @ViewBuilder label: @escaping () -> Label) {
        self.content = content
        self.label = label
        hasExpanded = false
        _isExpanded = .constant(false)
    }

    public init(isExpanded: Binding<Bool>, @ViewBuilder content: @escaping () -> Content, @ViewBuilder label: @escaping () -> Label) {
        self.content = content
        self.label = label
        hasExpanded = true
        _isExpanded = isExpanded
    }

    public var body: some View {
#if os(tvOS)
        Group {
            label()
            content()
        }
#else
        if hasExpanded {
            DisclosureGroup(isExpanded: $isExpanded, content: content, label: label)
        } else {
            DisclosureGroup(content: content, label: label)
        }
#endif
    }
}

#Preview("Disclosure group") {
    @Previewable @State var isExpanded = true
    DisclosureGroupTV(isExpanded: $isExpanded) {
        Text(verbatim: "The party has entered the dungeon.")
    } label: {
        Label {
            Text(verbatim: "Adventure notes")
        } icon: {
            Image(systemName: "book.closed")
        }
    }
    .padding()
}
