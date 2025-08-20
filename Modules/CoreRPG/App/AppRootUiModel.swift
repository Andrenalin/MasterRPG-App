// @copyright André Trettin

import SwiftUI

@Observable
public final class AppRootUiModel {
    public init(windowSize: CGSize = CGSize(width: 360, height: 800)) {
        self.windowSize = windowSize
    }
    
    public var windowSize: CGSize
}
