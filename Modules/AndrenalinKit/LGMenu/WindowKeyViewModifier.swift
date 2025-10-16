// @copyright André Trettin

import SwiftUI

#if os(tvOS)
public typealias AKKeyEquivalent = String
#else
public typealias AKKeyEquivalent = KeyEquivalent
#endif

struct WindowKeyViewModifier: ViewModifier {
    let key: AKKeyEquivalent
    
    func body(content: Content) -> some View {
        content
    }
}

