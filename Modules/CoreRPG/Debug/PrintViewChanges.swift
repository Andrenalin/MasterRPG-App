// @copyright André Trettin

import SwiftUI

public extension View {
    static func printViewChangesOnlyInDebug() {
        #if DEBUG
            let _ = Self._printChanges()
        #endif
    }

}
