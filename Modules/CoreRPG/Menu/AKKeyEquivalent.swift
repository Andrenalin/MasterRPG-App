// @copyright André Trettin

import SwiftUI

#if os(tvOS)
public typealias AKKeyEquivalent = String
#else
public typealias AKKeyEquivalent = KeyEquivalent
#endif
