// @copyright André Trettin

import Foundation

#if os(macOS)
import AppKit

public typealias AKColor = NSColor

#else
import UIKit

public typealias AKColor = UIColor
#endif
