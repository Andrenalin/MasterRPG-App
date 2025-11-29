// @copyright André Trettin

import SwiftUI

public struct BottomSafetyView: View {
    public init(space: CGFloat = 68) {
        self.space = space
    }

    public var space: CGFloat = 68
    public var body: some View {
        Color.clear.frame(height: 0)
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: space)
            }
    }
}
