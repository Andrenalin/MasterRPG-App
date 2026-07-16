// @copyright André Trettin

import CoreRPG
import SwiftUI

struct OverlayGameSideContent<Side: View, ToolBar: View, Dice: View>: View {
    let side: Side
    let toolbar: ToolBar
    let dice: Dice
    let showsDice: Bool

    var body: some View {
        HStack {
            side
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        .overlay(alignment: .topLeading) {
#if !os(visionOS)
            if showsDice {
                dice
                    .transition(.move(edge: .leading))
            }
#endif
        }
        .overlay(alignment: .bottomLeading) {
            toolbar
                .padding(.bottom, valueFor(iOS: 0, macOS: 12, tvOS: 0, visionOS: 0))
        }
    }
}

#Preview {
    OverlayGameSideContent(
        side: Color.red.frame(width: 180),
        toolbar: Button(action: {}) {
            Label {
                Text(verbatim: "Clear")
            } icon: {
                Image(systemName: "eraser")
            }
        },
        dice: Label {
            Text(verbatim: "Dice")
        } icon: {
            Image(systemName: "dice")
        },
        showsDice: true
    )
}
