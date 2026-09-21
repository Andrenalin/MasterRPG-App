// @copyright André Trettin

import CoreGraphics
import SwiftUI

#if os(macOS)
@MainActor @Observable
public final class OptionKeyDownModel: Sendable {
    public var isPressedOptionKey = false

    private var cancelEventHandler: Any?

    public init() {
        start()
    }

    // The local monitor keeps the handler alive until it is removed, so it must be removed here
    // (an isolated deinit may touch the main-actor state). See CODE_AUDIT_15 §5.14.
    isolated deinit {
        stop()
    }

    private func start() {
        guard cancelEventHandler == nil else { return }
        cancelEventHandler = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.isPressedOptionKey <=> (event.modifierFlags.rawValue & NSEvent.ModifierFlags.option.rawValue) != 0
            return event
        }
    }
    
    private func stop() {
        guard let cancelEventHandler else { return }
        NSEvent.removeMonitor(cancelEventHandler)
        self.cancelEventHandler = nil
    }
}

#else

@MainActor @Observable
public final class OptionKeyDownModel: Sendable {
    public var isPressedOptionKey = false

    private var cancelEventHandler: Any?

    public init() {}
    
    deinit {}
}

#endif

public struct OptionKeyPressedButton<Content: View>: View {
    public init(action: @escaping (Bool) -> Void, label: @escaping (Bool) -> Content) {
        self.action = action
        self.label = label
    }
    
    let action: (Bool) -> Void
    let label: (Bool) -> Content
    
    @Environment(OptionKeyDownModel.self) private var keyModel

    public var body: some View {
        Button {
            action(keyModel.isPressedOptionKey)
        } label: {
            label(keyModel.isPressedOptionKey)
        }
    }
}

#Preview {
    OptionKeyPressedButton(action: { _ in }) { isPressed in
        Label {
            Text(verbatim: isPressed ? "Alternate action" : "Primary action")
        } icon: {
            Image(systemName: "option")
        }
    }
    .environment(OptionKeyDownModel())
}
