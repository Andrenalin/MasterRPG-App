// @copyright André Trettin

import SwiftUI

public struct SectionGroupEditorView<Content: View, Header: View, Footer: View>: View {
    public let content: () -> Content
    public let header: () -> Header
    public let footer: () -> Footer

    public init(@ViewBuilder _ content: @escaping () -> Content, @ViewBuilder header: @escaping () -> Header, @ViewBuilder footer: @escaping () -> Footer) {
        self.content = content
        self.header = header
        self.footer = footer
    }

    public var body: some View {
        #if os(macOS)
            GroupBox {
                VStack(alignment: .leading, spacing: 16) {
                    content()                        
                        .frame(maxWidth: .infinity, alignment: .leading)

                    footer()
                        .font(.caption)
                }
                .padding()
            } label: {
                header()
            }
            .listRowSeparator(.hidden)
        #else
            Section(content: content, header: header, footer: footer)
        #endif
    }
}

public extension SectionGroupEditorView where Footer == EmptyView {
    init(@ViewBuilder _ content: @escaping () -> Content, @ViewBuilder header: @escaping () -> Header) {
        self.content = content
        self.header = header
        footer = { EmptyView() }
    }
}

public extension SectionGroupEditorView where Header == EmptyView {
    init(@ViewBuilder _ content: @escaping () -> Content, @ViewBuilder footer: @escaping () -> Footer) {
        self.content = content
        header = { EmptyView() }
        self.footer = footer
    }
}

public extension SectionGroupEditorView where Header == EmptyView, Footer == EmptyView {
    init(@ViewBuilder _ content: @escaping () -> Content) {
        self.content = content
        header = { EmptyView() }
        footer = { EmptyView() }
    }
}
