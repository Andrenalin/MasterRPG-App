// @copyright André Trettin

import SwiftUI

struct ShareItemViewModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    let isActive: Bool
    let allReported: Bool
    let feedBackEnabled: Bool
    let secondActionIcon: String?
    let action: () -> Void
    let secondAction: (() -> Void)?

    func body(content: Content) -> some View {
        HStack(spacing: 8) {
            if isActive {
                if feedBackEnabled {
                    SendFeedbackButton(allReported: allReported, secondActionIcon: secondActionIcon, action: action, secondAction: secondAction)
                } else {
                    if allReported {
                        buttonView
                            .buttonStyle(.bordered)
                    } else {
                        buttonView
                            .buttonStyle(.borderedProminent)
                    }
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
            Image(systemName: allReported ? secondActionIcon ?? "square.and.arrow.up" : "square.and.arrow.up")
                .symbolRenderingMode(.palette)
                .foregroundStyle(allReported ? .teal : .white, .white)
            #if !os(macOS)
                .frame(height: 24)
            #endif
        }
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(.rect)
        .accessibilityLabel(
            allReported && secondAction != nil
                ? Text("Perform follow-up action", bundle: .module)
                : Text("Share", bundle: .module)
        )
    }
}

public extension View {
    func shareListItem(isActive: Bool = false, allReported: Bool = false, feedBackEnabled: Bool = false, secondActionIcon: String? = nil, action: @escaping () -> Void, secondAction: (() -> Void)? = nil) -> some View {
        modifier(ShareItemViewModifier(isActive: isActive, allReported: allReported, feedBackEnabled: feedBackEnabled, secondActionIcon: secondActionIcon, action: action, secondAction: secondAction))
    }
}
