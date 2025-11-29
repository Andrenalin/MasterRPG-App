// @copyright André Trettin

import SwiftUI

struct SendFeedbackButton: View {
    let allReported: Bool
    let secondActionIcon: String?
    let action: () -> Void
    let secondAction: (() -> Void)?

    
    @State private var isSending: Bool = false
    @State private var isUpdating: Bool = false
    @State private var value: Double = 0
    
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
            withAnimation {
                isSending.toggle()
                if let secondAction, allReported == true {
                    secondAction()
                } else {                    
                    action()
                }
            }
        } label: {
            Image(systemName: allReported && secondActionIcon != nil ? secondActionIcon! : "square.and.arrow.up")
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
        .onChange(of: isSending) {
            guard isSending else { return }
            Task {
                await changeVariableValue()
            }
            withAnimation { isUpdating = true }
        }
        .onChange(of: isUpdating) {
            guard isUpdating else { return }
            Task {
                await responseTimeout()
            }
        }
    }
    
    func changeVariableValue() async {
        while !Task.isCancelled {
            if value >= 1 { value = 0 }
            try? await Task.sleep(for: .seconds(0.25))
            value += 0.25
        }
    }
    
    func responseTimeout() async {
        try? await Task.sleep(for: .seconds(1))
        isSending = false
        isUpdating = false
    }
}

#Preview {
    SendFeedbackButton(allReported: false, secondActionIcon: "gear") {} secondAction: {}
}
