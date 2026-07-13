// @copyright André Trettin

import AVFoundation
import AVKit
import SwiftUI


#if os(visionOS)
struct RoutePickerView: View {
    var body: some View {
        EmptyView()
    }
}

#Preview {
    RoutePickerView()
}

#elseif !os(macOS)
import UIKit

struct RoutePickerView: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView(frame: .zero)
        view.activeTintColor = .systemTeal
        return view
    }

    func updateUIView(_ view: AVRoutePickerView, context: Context) {
    }
}

#Preview {
    RoutePickerView()
}
#endif
