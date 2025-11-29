// @copyright André Trettin

import CoreRPG
import SwiftUI

struct SpaceImporterView: View {
    @Binding var showImporter: Bool
    
    @State private var showScanner: Bool = false
    @State private var canScan: Bool = false
    
    var body: some View {
        HStack {
            scanView
            
            ImageOverlayButton(icon: "folder\(showImporter ? ".fill" : "")") { showImporter.toggle() }
                .contentTransition(.symbolEffect(.replace.wholeSymbol))
        }
        .task {
#if os(iOS) && !targetEnvironment(simulator)
            canScan = await ConfigCaptureObject.isSupported()
#endif
        }
    }
        
    @MainActor
    @ViewBuilder
    var scanView: some View {
#if os(iOS) && !targetEnvironment(simulator)
        if canScan {
            ImageOverlayButton(icon: "doc.viewfinder\(showScanner ? ".fill" : "")") { showScanner.toggle() }
                .fullScreenCover(isPresented: $showScanner) {
                    Scanner3DRootView()
                }
        } else {
            EmptyView()
        }
#else
        EmptyView()
#endif
    }
}

#Preview {
    Color
        .teal
        .frame(width: 256, height: 256)
        .overlay(SpaceImporterView(showImporter: .constant(true)), alignment: .bottom)
}
