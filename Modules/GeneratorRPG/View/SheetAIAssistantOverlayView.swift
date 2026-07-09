// @copyright André Trettin

#if !os(tvOS)
import CoreRPG
import FoundationModels
import SwiftUI

/// Bottom overlay for a detail editor's SheetRootView: a small "Ask AI" trigger that
/// expands, in place, into a chat composer (no separate sheet/window, no header chrome).
/// On send, the resulting blocks are added as temporary, unpersisted preview entries
/// (isGeneratedAnswer) directly into the SAME `rootModel` already driving the visible
/// sheet tree — not a second, parallel SheetRootModel. Tapping a preview row (see
/// SheetEntryView/SheetView) is what actually persists it via the EditController.
public struct SheetAIAssistantOverlayView: View {
    public init(module: NetworkModules, itemId: UUID, rootModel: SheetRootModel) {
        self.module = module
        self.itemId = itemId
        self.rootModel = rootModel
    }

    let module: NetworkModules
    let itemId: UUID
    let rootModel: SheetRootModel

    @Environment(GeneratorRootModel.self) private var generatorRoot

    @State private var isComposing = false
    @State private var messageText = ""
    @FocusState private var isTextFieldFocused: Bool
    /// Captured at send time: if an entry was selected when the message was sent, the
    /// resulting blocks are added as its subentries; otherwise they go under the root.
    @State private var targetParent: SheetModel?

    private var generatorController: AdventureGeneratorController {
        generatorRoot.generatorController(for: module, itemId: itemId)
    }

    public var body: some View {
        Group {
            if isComposing {
                composer
            } else {
                openButton
            }
        }
        // extracted updates on every partial streaming token — only persist once the
        // stream has actually finished (the isExtracting true -> false transition),
        // otherwise every partial token batch would create duplicate saved entries.
        .onChange(of: generatorController.model.isExtracting) { wasExtracting, isExtracting in
            guard wasExtracting, !isExtracting else { return }
            persistGeneratedBlocks()
        }
    }

    private var openButton: some View {
        Button {
            isComposing = true
            isTextFieldFocused = true
        } label: {
            Label { Text("Ask AI", bundle: .module) } icon: { Image(systemName: NetworkModules.generator.icon) }
        }
        .buttonStyle(.borderedProminent)
        .tint(module.tint)
        #if !os(visionOS)
        .glassEffectAll(.regular.tint(module.tint).interactive())
        #endif
        .padding()
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            ChatInputView(
                messageText: $messageText,
                generatorController: generatorController,
                isTextFieldFocused: $isTextFieldFocused,
                sendMessageAction: sendMessage
            )

            Button {
                isComposing = false
                isTextFieldFocused = false
            } label: {
                Label { Text("Close", bundle: .module) } icon: { Image(systemName: "xmark.circle.fill") }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .padding(.bottom, 12)
            .padding(.trailing, 8)
        }
        .padding(.horizontal)
    }

    private func sendMessage(_ message: String) {
        targetParent = rootModel.selectedEntry
        generatorController.generateExtractor()
        let prompt = """
        Create a few sheet entries from this request. Return concise blocks, each with a \
        useful title and playable content, suitable for saving directly into the sheet. \
        One block is fine if that's all the request calls for.

        Request:
        \(message)
        """
        generatorController.extract(message: prompt)
    }

    @MainActor
    private func persistGeneratedBlocks() {
        let batchID = UUID().uuidString
        let parent = targetParent ?? rootModel.sheetModel
        let newEntries: [SheetModel] = generatorController.model.extracted.compactMap { block in
            let title = block.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let content = block.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !title.isEmpty || !content.isEmpty else { return nil }
            let typeId: NetworkModules = parent.source.typeId == .none ? module : parent.source.typeId
            let source = ItemRowModel(itemId: parent.source.itemId, entryId: UUID(), typeId: typeId)
            let entry = SheetModel(
                source: source,
                destination: parent.source,
                level: parent.level + 1,
                name: title.isEmpty ? String(localized: "Generated Entry", bundle: .module) : title,
                description: content,
                entries: []
            )
            entry.isGeneratedAnswer = true
            entry.generatedBatchID = batchID
            return entry
        }
        parent.entries.append(contentsOf: newEntries)
        if let firstEntryId = newEntries.first?.source.entryId {
            rootModel.setScrollEntryId(source: parent.source, entryId: firstEntryId)
        }
        targetParent = nil
    }
}
#endif
