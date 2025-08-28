// @copyright André Trettin

import SwiftUI

public struct DropItemArea<Content: View>: View {
    public init(@ViewBuilder contentView: () -> Content, dropAction: @escaping ([LinkData]) -> Bool) {
        self.contentView = contentView()
        self.dropAction = dropAction
    }

    let contentView: Content
    let dropAction: ([LinkData]) -> Bool

    @State private var dropBackgroundColor: Color = .clear
    @State private var dropForegroundColor: Color = .primary

    public var body: some View {
        contentView
            .padding(4)
            .foregroundStyle(dropForegroundColor)
            .background {
                RoundedRectangle(cornerRadius: 24, style: .continuous).fill(dropBackgroundColor)
            }
#if !os(tvOS)
            .dropDestination(for: LinkData.self) { items, _ in
                guard !items.isEmpty else { return false }
                return dropAction(items)
            } isTargeted: { inDropArea in
                dropBackgroundColor = inDropArea ? .accentColor : .clear
                dropForegroundColor = inDropArea ? .white : .primary
            }
#endif
    }
}
