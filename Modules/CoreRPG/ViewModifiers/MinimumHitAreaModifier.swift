// @copyright André Trettin

import SwiftUI

public extension View {
    /// Hit-tests at least `minimumSize` × `minimumSize` pt (HIG minimum touch target)
    /// while keeping the view's own layout size — unlike `.frame(minWidth:minHeight:)`,
    /// which makes a compact control (and the row containing it) grow to that size.
    ///
    /// Apply it to a `Button`'s label (after any padding), so the enlarged shape is the
    /// one the button itself hit-tests with.
    nonisolated func minimumHitArea(_ minimumSize: CGFloat = 44) -> some View {
        contentShape(MinimumHitAreaShape(minimumSize: minimumSize))
    }
}

/// A hit-test rectangle centred on the view that is never smaller than the
/// HIG minimum touch target. Used as a `contentShape` it enlarges the tappable
/// area of a compact control without changing its layout size.
struct MinimumHitAreaShape: Shape {
    var minimumSize: CGFloat = 44

    func path(in rect: CGRect) -> Path {
        let width = max(rect.width, minimumSize)
        let height = max(rect.height, minimumSize)
        return Path(CGRect(x: rect.midX - width / 2, y: rect.midY - height / 2, width: width, height: height))
    }
}

#Preview {
    Button("Delete", systemImage: "minus.circle.fill") {}
        .labelStyle(.iconOnly)
        .imageScale(.large)
        .padding(8)
        .minimumHitArea()
        .border(.secondary)
        .padding()
}
