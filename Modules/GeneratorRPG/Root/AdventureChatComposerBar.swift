// @copyright André Trettin

import CoreRPG
import SwiftUI

struct AdventureChatComposerBar: View {
    @Binding var prompt: String
    let generatorController: AdventureGeneratorController
    @FocusState.Binding var isTextFieldFocused: Bool
    let canExtract: Bool
    let isExtracting: Bool
    let prepareForRequestAction: () -> Void
    let requestBlocksAction: (String) -> Void
    let extractAction: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            ChatInputView(
                messageText: $prompt,
                generatorController: generatorController,
                isTextFieldFocused: $isTextFieldFocused,
                prepareForRequestAction: prepareForRequestAction,
                sendMessageAction: requestBlocksAction
            )

            Button(
                LocalizedStringResource("Extract", bundle: .module),
                systemImage: "list.bullet.clipboard",
                action: extractAction
            )
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .disabled(!canExtract || isExtracting)
                .padding(.trailing)
                .padding(.bottom)
                .help(Text("Extract adventure blocks", bundle: .module))
        }
        .background(.bar)
    }
}

#Preview(traits: .mockData) {
    @Previewable @Environment(GeneratorRootModel.self) var root
    @Previewable @State var prompt = "Add a hidden rival"
    @Previewable @FocusState var isFocused: Bool
    AdventureChatComposerBar(
        prompt: $prompt,
        generatorController: root.generatorController(for: .adventure, itemId: AdventureChatPreviewData.sheetModel.source.itemId),
        isTextFieldFocused: $isFocused,
        canExtract: true,
        isExtracting: false,
        prepareForRequestAction: {},
        requestBlocksAction: { _ in },
        extractAction: {}
    )
}
