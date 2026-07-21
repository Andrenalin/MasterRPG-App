import CoreRPG
import SwiftUI

struct BatteryView: View {
    
    @State private var batteryLevel: Float = 0.0
    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        Text("Battery", bundle: .module)
    }
}

#Preview {
    BatteryView()
}
