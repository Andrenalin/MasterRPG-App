// @copyright André Trettin

import SwiftUI

extension View {
    nonisolated public func inspectorAll<V>(isPresented: Binding<Bool>, @ViewBuilder content: () -> V) -> some View where V : View {
#if os(tvOS) || os(visionOS)
        self
#else
        inspector(isPresented: isPresented, content: content)
#endif
    }
}
