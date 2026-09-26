// @copyright André Trettin

import SwiftUI

struct SendFeedbackButton: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    let allReported: Bool
    let module: NetworkModules
    let secondActionIcon: String?
    let action: () -> Void
    let secondAction: (() -> Void)?

    
    @State private var isSending: Bool = false
    @State private var isUpdating: Bool = false
    @State private var value: Double = 0

    /// Step interval for the "wifi" variable-value symbol animation — 4 steps of 0.25 per
    /// full cycle. See CODE_AUDIT §9.14.
    private static let wifiSymbolTickInterval: Duration = .seconds(0.25)
    /// Resets the sending state if no response arrives in time. See CODE_AUDIT §9.14.
    private static let sendingResponseTimeout: Duration = .seconds(1)

    var body: some View {
        if allReported {
            SendFeedbackButtonButtonView(allReported: allReported, module: module, secondActionIcon: secondActionIcon, action: action, secondAction: secondAction, value: value, isSending: $isSending, isUpdating: $isUpdating, changeVariableValue: changeVariableValue, responseTimeout: responseTimeout)
                .buttonStyle(.bordered)
        } else {
            SendFeedbackButtonButtonView(allReported: allReported, module: module, secondActionIcon: secondActionIcon, action: action, secondAction: secondAction, value: value, isSending: $isSending, isUpdating: $isUpdating, changeVariableValue: changeVariableValue, responseTimeout: responseTimeout)
                .buttonStyle(.borderedProminent)
        }
    }

    func changeVariableValue() async {
        while isSending && !Task.isCancelled {
            if value >= 1 { value = 0 }
            try? await Task.sleep(for: Self.wifiSymbolTickInterval)
            value += 0.25
        }
    }
    
    func responseTimeout() async {
        // A cancelled (superseded) timeout must not reset the newer send's state.
        guard (try? await Task.sleep(for: Self.sendingResponseTimeout)) != nil else { return }
        isSending = false
        isUpdating = false
    }
}

#Preview {
    SendFeedbackButton(allReported: false, module: .audio, secondActionIcon: "gear") {} secondAction: {}
}

// MARK: - Extracted subviews (CODE_AUDIT §8.3)

private struct SendFeedbackButtonButtonView: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    let allReported: Bool
    let module: NetworkModules
    let secondActionIcon: String?
    let action: () -> Void
    let secondAction: (() -> Void)?
    let value: Double
    @Binding var isSending: Bool
    @Binding var isUpdating: Bool
    let changeVariableValue: () async -> Void
    let responseTimeout: () async -> Void

    var body: some View {
        Button {
            guard !isSending else { return }
            withAnimation(accessibilityReduceMotion ? nil : .default) {
                isSending.toggle()
                if let secondAction, allReported == true {
                    secondAction()
                } else {
                    action()
                }
            }
        } label: {
            Image(systemName: allReported ? secondActionIcon ?? "eye" : "square.and.arrow.up")
                .imageScale(.large)
                .symbolRenderingMode(.palette)
                .foregroundStyle(allReported ? .teal : .white, .white)
                .symbolEffect(.disappear, isActive: isSending)
                .overlay {
                    Image(systemName: "wifi", variableValue: value)
                        .imageScale(.large)
                        .symbolEffect(.disappear, isActive: !isSending)
                }
        }
        .selectedRoundButton(title: String(localized: "Share", bundle: .module), module: module, isSelected: allReported)
        .accessibilityLabel(
            allReported && secondAction != nil
                ? Text("Perform follow-up action", bundle: .module)
                : Text("Share", bundle: .module)
        )
        .onChange(of: isSending) {
            guard isSending else { return }
            withAnimation(accessibilityReduceMotion ? nil : .default) { isUpdating = true }
        }
        // `.task(id:)` instead of unstructured Tasks: a new send cancels the previous send's
        // animation and timeout, so an earlier timeout can no longer reset a later send's
        // state. See CODE_AUDIT_18 §3.19.
        .task(id: isSending) {
            guard isSending, !accessibilityReduceMotion else { return }
            await changeVariableValue()
        }
        .task(id: isUpdating) {
            guard isUpdating else { return }
            await responseTimeout()
        }
    }
}
