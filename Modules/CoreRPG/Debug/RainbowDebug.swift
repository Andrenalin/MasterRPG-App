// @copyright André Trettin

import SwiftUI

public extension Color {
    static var random: Color {
        Color(red: .random(in: 0 ... 1), green: .random(in: 0 ... 1), blue: .random(in: 0 ... 1))
    }
}

public extension View {
    func rainbowDebug() -> some View {
        #if VIEW_DEBUG
            background(Color.random)
        #else
            self
        #endif
    }

    static func printViewChangesOnlyInDebug() {
        #if DEBUG
            let _ = Self._printChanges()
            //let _ = Self._logChanges()
        #endif
    }

}
