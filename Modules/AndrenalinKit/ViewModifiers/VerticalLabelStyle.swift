// @copyright André Trettin

import SwiftUI

public struct VerticalLabelStyle: LabelStyle {
    public func makeBody(configuration: Configuration) -> some View {
        VStack {
            configuration.icon
            configuration.title
        }
    }
}

public extension LabelStyle where Self == VerticalLabelStyle {
    static var vertical: VerticalLabelStyle {
        VerticalLabelStyle()
    }
}
