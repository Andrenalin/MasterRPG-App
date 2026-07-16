// @copyright André Trettin

import SwiftUI

public extension View {
    func detailSectionRow<Header: View>(isActive: Bool = true, color: Color = .blue.opacity(0.6), @ViewBuilder header: @escaping () -> Header) -> some View {
        Group {
            if isActive {
                modifier(DetailSectionRowViewModifier(color: color, header: header))
            } else {
                self
            }
        }
    }
}

struct DetailSectionRowViewModifier<Header: View>: ViewModifier {
    let color: Color
    let header: () -> Header

    func body(content: Content) -> some View {
        GroupBoxTV(isCard: true) {
            VStack(alignment: .leading, spacing: 8) {
                content
                    .padding(8)
            }
            .background(RoundedRectangle(cornerRadius: 12).fill(color))
            #if os(macOS)
                .padding()
            #endif
                .rainbowDebug()
        } label: {
            header()
                .rainbowDebug()
        }
    }
}

struct CompactSectionRowViewModifier<Header: View>: ViewModifier {
    let isEditing: Bool
    let embbed: Bool
    let color: Color
    let header: () -> Header

    func body(content: Content) -> some View {
        #if os(macOS)
            if embbed {
                VStack(alignment: .leading, spacing: 8) {
                    header()
                        .padding(8)
                        .rainbowDebug()

                    content
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 12).fill(color))
                        .rainbowDebug()
                }
            } else {
                grouppedView(content: content)
            }
        #else
            grouppedView(content: content)
        #endif
    }

    private func grouppedView(content: Content) -> some View {
        GroupBoxTV(isCard: true) {
            if isEditing {
                VStack(alignment: .leading, spacing: 8) {
                    content
                        .padding(8)
                }
                .background(RoundedRectangle(cornerRadius: 12).fill(color))
                .rainbowDebug()
            }
        } label: {
            header()
                .rainbowDebug()
        }
    }
}

#Preview {
    Text(verbatim: "Row Content").detailSectionRow(color: .yellow) {
        Text(verbatim: "Title of this section")
    }
}
