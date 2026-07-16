// @copyright André Trettin

import SwiftUI

#Preview("Front") {
    FlipView {
        Label {
            Text(verbatim: "Front")
        } icon: {
            Image(systemName: "rectangle.front.fill")
        }
    } back: {
        Label {
            Text(verbatim: "Back")
        } icon: {
            Image(systemName: "rectangle.back.fill")
        }
    }
    .padding()
}

#Preview("Back") {
    FlipView(isFlipped: true) {
        Label {
            Text(verbatim: "Front")
        } icon: {
            Image(systemName: "rectangle.front.fill")
        }
    } back: {
        Label {
            Text(verbatim: "Back")
        } icon: {
            Image(systemName: "rectangle.back.fill")
        }
    }
    .padding()
}

public struct FlipView<Front: View, Back: View>: View {
    public var isFlipped: Bool
    public var front: () -> Front
    public var back: () -> Back

    public init(isFlipped: Bool = false, @ViewBuilder front: @escaping () -> Front, @ViewBuilder back: @escaping () -> Back) {
        self.isFlipped = isFlipped
        self.front = front
        self.back = back
    }

    public var body: some View {
        ZStack {
            front()
                .rotation3DEffect(.degrees(isFlipped ? 180 : 0), axis: (x: 0, y: 1, z: 0))
                .opacity(isFlipped ? 0 : 1)
                .accessibilityHidden(isFlipped)

            back()
                .rotation3DEffect(.degrees(isFlipped ? 0 : -180), axis: (x: 0, y: 1, z: 0))
                .opacity(isFlipped ? 1 : 0)
                .accessibilityHidden(!isFlipped)
        }
    }
}
