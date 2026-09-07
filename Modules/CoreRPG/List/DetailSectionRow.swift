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

#Preview {
    Text(verbatim: "Row Content").detailSectionRow(color: .yellow) {
        Text(verbatim: "Title of this section")
    }
}
