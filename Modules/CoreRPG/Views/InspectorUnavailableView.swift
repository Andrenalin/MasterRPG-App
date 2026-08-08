// @copyright André Trettin

import SwiftUI

#Preview {
    InspectorUnavailableView()
}

public struct InspectorUnavailableView: View {
    public init() {}
    
    public var body: some View {
        ContentUnavailableView {
            Label {
                Text("No Inspector for this item", bundle: .module)
            } icon: {
                Image(systemName: "scope")
            }
        }
    }
}
