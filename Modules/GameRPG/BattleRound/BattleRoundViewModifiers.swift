// @copyright André Trettin

import SwiftUI

extension View {
    @ViewBuilder
    func battleInlineNavigationTitle() -> some View {
#if os(iOS) || os(visionOS)
        navigationBarTitleDisplayMode(.inline)
#else
        self
#endif
    }
}
