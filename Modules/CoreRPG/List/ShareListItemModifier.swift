// @copyright André Trettin

import SwiftUI

struct ShareItemViewModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    let isActive: Bool
    let allReported: Bool
    let feedBackEnabled: Bool
    let module: NetworkModules
    let secondActionIcon: String?
    let action: () -> Void
    let secondAction: (() -> Void)?

    func body(content: Content) -> some View {
        HStack(spacing: 8) {
            if isActive {
                if feedBackEnabled {
                    SendFeedbackButton(allReported: allReported, module: module, secondActionIcon: secondActionIcon, action: action, secondAction: secondAction)
                } else {
                    buttonView
                }
            }

            content
                .contentShape(.rect)
        }
        .animation(accessibilityReduceMotion ? nil : .default, value: isActive)
    }
    
    private var buttonView: some View {
        Button {
            if let secondAction, allReported == true {
                secondAction()
            } else {
                action()
            }
        } label: {
            Image(systemName: allReported ? secondActionIcon ?? "eye" : "square.and.arrow.up")
                .symbolRenderingMode(.palette)
                .foregroundStyle(allReported ? .teal : .white, .white)
            #if !os(macOS)
                .frame(height: 24)
            #endif
        }
        .selectedRoundButton(title: String(localized: "Share", bundle: .module), module: module, isSelected: allReported)
        .accessibilityLabel(
            allReported && secondAction != nil
                ? Text("Perform follow-up action", bundle: .module)
                : Text("Share", bundle: .module)
        )
    }
}

public extension View {
    func shareListItem(isActive: Bool = false, allReported: Bool = false, feedBackEnabled: Bool = false, module: NetworkModules, secondActionIcon: String? = nil, action: @escaping () -> Void, secondAction: (() -> Void)? = nil) -> some View {
        modifier(ShareItemViewModifier(isActive: isActive, allReported: allReported, feedBackEnabled: feedBackEnabled, module: module, secondActionIcon: secondActionIcon, action: action, secondAction: secondAction))
    }
}
