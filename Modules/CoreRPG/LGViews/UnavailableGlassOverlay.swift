// @copyright André Trettin

import SwiftUI

struct UnavailableGlassOverlay<Content: View>: View {
    let content: Content
    let isUnavailable: Bool
    
    init(isUnavailable: Bool, @ViewBuilder content: () -> Content) {
        self.isUnavailable = isUnavailable
        self.content = content()
    }
    
    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        
        content
            .disabled(isUnavailable)
            .overlay {
                Color.primary.opacity(isUnavailable ? 0.2 : 0)
                    .accessibilityHidden(true)
                
                ContentUnavailableView.search
                    .padding()
#if os(visionOS)
                    .glassBackgroundEffect(in: .rect(cornerRadius: 28, style: .continuous))
#else
                    .glassEffect(.regular.interactive())
#endif
                    .padding()
                    .opacity(isUnavailable ? 1 : 0)
                    .allowsHitTesting(isUnavailable)
                    .accessibilityHidden(!isUnavailable)
            }
    }
}

#Preview {
    UnavailableGlassOverlay(isUnavailable: true) {
        Text(verbatim: "Search results")
            .padding()
    }
}
