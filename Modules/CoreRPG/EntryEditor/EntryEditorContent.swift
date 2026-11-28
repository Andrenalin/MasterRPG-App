// @copyright André Trettin

import SwiftUI

struct EntryEditorContent<LinkType: LinkDataTransferable>: View {
    init(editController: any EntryDataEditable, editorModel: SheetEditorModel, itemId: UUID, entry: any EntryDataAccessible, linkTypes: LinkType.Type) {
        self.editController = editController
        self.editorModel = editorModel
        self.itemId = itemId
        self.entry = entry
        self.linkTypes = linkTypes
        
        self._editModel = State(wrappedValue: TextEditModel(linkRegisterController: editController.linkRegisterController))
    }
    
    let editController: any EntryDataEditable
    let editorModel: SheetEditorModel
    let itemId: UUID
    let entry: any EntryDataAccessible
    let linkTypes: LinkType.Type
    
    @FocusState private var currentFocus: EntryEditorFocusField?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    @State private var editModel: TextEditModel
    
    var body: some View {
        GlassEffectContainerAll {
            EntryEditorContentEditorCardView(editController: editController, editorModel: editorModel, itemId: itemId, editModel: editModel, entry: entry, linkTypes: linkTypes, currentFocus: $currentFocus)
                .textInputUndo()
        }
        .frame(maxWidth: 800)
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        // A change of the stored entry keeps what the user is typing. See CODE_AUDIT_Edit_Save §8.1.
        .onChange(of: entry.content, initial: true) {
            syncEditModel()
        }
        .onChange(of: entry.name) {
            syncEditModel()
        }
        .background {
            Button {
                withAnimation(reduceMotion ? nil : .default) {
                    editorModel.entryId = nil
                }
            } label: {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
            }
            .buttonStyle(.plain)
            .accessibilityHidden(true)
        }
        .task {
#if !os(tvOS)
            // Small delay to ensure smooth appearance
            try? await Task.sleep(for: EditorFocus.autoFocusDelay)
            currentFocus = .name
#endif
        }
    }
    
    private func syncEditModel() {
        editModel.sync(entry: entry, source: ItemRowModel(itemId: itemId, entryId: entry.id, typeId: editorModel.module))
    }
}

private extension View {
    @ViewBuilder
    func entryEditorGlass(tint: Color) -> some View {
#if os(visionOS)
        self
#else
        glassEffectAll(
            .regular.tint(tint.opacity(0.18)),
            in: .rect(cornerRadius: 28, style: .continuous)
        )
#endif
    }
}

enum EntryEditorFocusField {
    case name
    case information
}

#Preview {
    EntryEditorContent(
        editController: FakeEditController.fake,
        editorModel: SheetEditorModel(),
        itemId: UUID(),
        entry: FakeEntryModel.empty,
        linkTypes: EmptyLinkTransferable.self
    )
}

// MARK: - Extracted subviews (CODE_AUDIT §8.3)

private struct EntryEditorContentEditorCardView<LinkType: LinkDataTransferable>: View {
    // Scaled with Dynamic Type instead of fixed points. See CODE_AUDIT_29 §8.7.
    @ScaledMetric private var padding20: CGFloat = 20
    @ScaledMetric private var spacing16: CGFloat = 16
    let editController: any EntryDataEditable
    let editorModel: SheetEditorModel
    let itemId: UUID
    let editModel: TextEditModel
    let entry: any EntryDataAccessible
    let linkTypes: LinkType.Type
    let currentFocus: FocusState<EntryEditorFocusField?>.Binding

    @Environment(\.appTheme) private var theme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(alignment: .leading, spacing: spacing16) {
            EntryEditorHeaderView(
                editController: editController,
                editorModel: editorModel,
                itemId: itemId,
                editModel: editModel,
                entry: entry,
                linkTypes: linkTypes
            )

            EntryNameEditor(editModel: editModel, currentFocus: currentFocus)

            EntryContentEditor(editModel: editModel, currentFocus: currentFocus)
        }
        .padding(padding20)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(theme.panelColor.opacity(reduceTransparency ? 1 : 0.58))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(
                    theme.tint(for: editorModel.module).opacity(0.45),
                    lineWidth: 1
                )
        }
        .entryEditorGlass(tint: theme.background(for: editorModel.module))
        .shadow(color: .black.opacity(0.24), radius: 24, y: 12)
        .containerShape(.rect(cornerRadius: 28, style: .continuous))
    }
}
