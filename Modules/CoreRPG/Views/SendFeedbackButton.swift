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
            buttonView
                .buttonStyle(.bordered)
        } else {
            buttonView
                .buttonStyle(.borderedProminent)
        }
    }
    
    var buttonView: some View {
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
            if !accessibilityReduceMotion {
                Task {
                    await changeVariableValue()
                }
            }
            withAnimation(accessibilityReduceMotion ? nil : .default) { isUpdating = true }
        }
        .onChange(of: isUpdating) {
            guard isUpdating else { return }
            Task {
                await responseTimeout()
            }
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
        try? await Task.sleep(for: Self.sendingResponseTimeout)
        isSending = false
        isUpdating = false
    }
}

#Preview {
    SendFeedbackButton(allReported: false, module: .audio, secondActionIcon: "gear") {} secondAction: {}
}
