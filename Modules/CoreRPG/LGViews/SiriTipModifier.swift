// @copyright André Trettin

#if os(iOS) || os(visionOS)

import AppIntents
import SwiftUI

public extension View {
    /// Shows Siri's tip for `intent` under the view until the user closes it; the choice is kept
    /// under `storageKey`. Only for intents the app lists as App Shortcuts with a phrase.
    /// `SiriTipView` is not available on macOS and tvOS. See CODE_AUDIT_AppIntents2 §8.2.
    func siriTip(for intent: some AppIntent, storageKey: String) -> some View {
        modifier(SiriTipModifier(intent: intent, storageKey: storageKey))
    }
}

private struct SiriTipModifier<Intent: AppIntent>: ViewModifier {
    let intent: Intent
    @AppStorage private var isVisible: Bool

    init(intent: Intent, storageKey: String) {
        self.intent = intent
        _isVisible = AppStorage(wrappedValue: true, storageKey)
    }

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom) {
            SiriTipView(intent: intent, isVisible: $isVisible)
#if os(visionOS)
                // The tip has no background of its own on visionOS, so the scrolled content shows
                // through it: it stands on glass, off the window's bottom edge.
                .padding()
                .glassBackgroundEffect(in: .rect(cornerRadius: 28, style: .continuous))
                .scenePadding(.bottom)
#endif
                .scenePadding(.horizontal)
        }
    }
}

#endif
