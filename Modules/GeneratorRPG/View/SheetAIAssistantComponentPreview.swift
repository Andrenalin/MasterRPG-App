// @copyright André Trettin

#if !os(tvOS)
import CoreRPG
import SwiftUI

struct SheetAIAssistantComponentPreview: View {
    @Namespace private var namespace
    @State private var message = "Create a dramatic encounter"
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack {
            SheetAIAssistantOpenButton(module: .adventure, glassNamespace: namespace, action: {})
            SheetAIAssistantMiniComposer(
                module: .adventure,
                messageText: $message,
                availability: SheetAIGenerationController().availability,
                isGenerating: false,
                isTextFieldFocused: $isFocused,
                submitAction: {}
            )
            SheetAIAssistantComposer(
                module: .adventure,
                messageText: $message,
                availability: SheetAIGenerationController().availability,
                isGenerating: false,
                canSubmit: true,
                isTextFieldFocused: $isFocused,
                glassNamespace: namespace,
                submitAction: {},
                closeAction: {}
            )
        }
    }
}

#Preview("Sheet AI Components") {
    SheetAIAssistantComponentPreview()
}
#endif
