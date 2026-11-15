// @copyright André Trettin

import SwiftUI

/// Shown where a 3D object would appear on Apple TV, which has no 3D object viewer. Without it a
/// revealed object left a blank screen with no explanation. See CODE_AUDIT_26 §5.45.
struct SpaceUnsupportedView: View {
    var body: some View {
        ContentUnavailableView {
            Label {
                Text("3D Objects Are Not Shown on Apple TV", bundle: .module)
            } icon: {
                Image(systemName: "cube")
            }
        } description: {
            Text("The Game Master revealed a 3D object. Open it on an iPhone, iPad, Mac or Apple Vision Pro.", bundle: .module)
        }
    }
}

#Preview {
    SpaceUnsupportedView()
}
