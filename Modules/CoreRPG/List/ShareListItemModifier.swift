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
                    ShareItemViewModifierButtonView(allReported: allReported, module: module, secondActionIcon: secondActionIcon, action: action, secondAction: secondAction)
                }
            }

            content
                .contentShape(.rect)
        }
        .animation(accessibilityReduceMotion ? nil : .default, value: isActive)
    }
}

public extension View {
    func shareListItem(isActive: Bool = false, allReported: Bool = false, feedBackEnabled: Bool = false, module: NetworkModules, secondActionIcon: String? = nil, action: @escaping () -> Void, secondAction: (() -> Void)? = nil) -> some View {
        modifier(ShareItemViewModifier(isActive: isActive, allReported: allReported, feedBackEnabled: feedBackEnabled, module: module, secondActionIcon: secondActionIcon, action: action, secondAction: secondAction))
    }
}

// MARK: - Shared share button parts

extension View {
    /// The round share button look shared by the list share button and the feedback button:
    /// selected while everything is reported, with the follow-up action named when it exists.
    /// See CODE_AUDIT_26 §9.24.
    func shareRoundButton(allReported: Bool, module: NetworkModules, hasSecondAction: Bool) -> some View {
        selectedRoundButton(title: String(localized: "Share", bundle: .module), module: module, isSelected: allReported)
            .accessibilityLabel(
                allReported && hasSecondAction
                    ? Text("Perform follow-up action", bundle: .module)
                    : Text("Share", bundle: .module)
            )
    }
}

/// The share icon, or the second action's icon once everything is reported.
func shareSymbolName(allReported: Bool, secondActionIcon: String?) -> String {
    allReported ? secondActionIcon ?? "eye" : "square.and.arrow.up"
}

// MARK: - Extracted subviews (CODE_AUDIT §8.3)

private struct ShareItemViewModifierButtonView: View {
    /// Grows with Dynamic Type instead of a fixed 24 pt. See CODE_AUDIT_18 §8.3.
    @ScaledMetric private var iconSize: CGFloat = 24
    let allReported: Bool
    let module: NetworkModules
    let secondActionIcon: String?
    let action: () -> Void
    let secondAction: (() -> Void)?

    var body: some View {
        Button {
            if let secondAction, allReported == true {
                secondAction()
            } else {
                action()
            }
        } label: {
            Image(systemName: shareSymbolName(allReported: allReported, secondActionIcon: secondActionIcon))
                .foregroundStyle(allReported ? Color.white : Color.primary)
            #if !os(macOS)
                .frame(height: iconSize)
            #endif
        }
        .shareRoundButton(allReported: allReported, module: module, hasSecondAction: secondAction != nil)
    }
}
