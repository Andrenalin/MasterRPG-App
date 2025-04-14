// @copyright André Trettin

import SwiftUI

@MainActor @Observable
public final class WindowStateModel {
    public init() {}
    
    public var openWindowState: [NetworkModules: Bool]  = [:]
    public var spaceImmersiveView: Bool = false
}
