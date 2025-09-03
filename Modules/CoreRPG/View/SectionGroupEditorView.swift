// @copyright André Trettin

import SwiftUI

public struct SectionGroupEditorView<Content: View, Header: View, Footer: View>: View {
    public let content: Content
    public let header: Header
    public let footer: Footer

    public init(@ViewBuilder _ content: () -> Content, @ViewBuilder header: () -> Header = EmptyView.init, @ViewBuilder footer: () -> Footer = EmptyView.init) {
        self.content = content()
        self.header = header()
        self.footer = footer()
    }

    public var body: some View {
#if os(macOS)
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)

                footer
                    .font(.caption)
            }
            .padding()
        } label: {
            header
        }
        .listRowSeparator(.hidden)
#else
        Section { content } header: { header } footer: { footer }
#endif
    }
}
