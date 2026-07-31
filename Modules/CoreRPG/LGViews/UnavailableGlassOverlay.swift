// @copyright André Trettin

import SwiftUI

struct UnavailableGlassOverlay<Content: View>: View {
    let content: Content
    let isUnavailable: Bool
    
    init(isUnavailable: Bool, @ViewBuilder content: () -> Content) {
        self.isUnavailable = isUnavailable
        self.content = content()
    }
    
    @Environment(\.appTheme) private var theme
    
    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        
        content
            .disabled(isUnavailable)
            .overlay {
                
                ContentUnavailableView.search
                    .padding()
#if os(visionOS)
                    .glassBackgroundEffect(in: .rect(cornerRadius: 28, style: .continuous))
#else
                    .glassEffect(.clear.tint(theme.accentColor))
#endif
                    .padding()
                    .frame(width: 200, height: 400)
                    .opacity(isUnavailable ? 1 : 0)
                    .allowsHitTesting(isUnavailable)
                    .accessibilityHidden(!isUnavailable)
            }
    }
}

#Preview {
    UnavailableGlassOverlay(isUnavailable: true) {
        ZStack {
            Color.blue
            
            Text(verbatim: "Search results")
                .padding()
        }
    }
}
