// @copyright André Trettin

import SwiftUI

struct EntryEditorContent<LinkType: LinkDataTransferable>: View {
    init(editController: any EntryDataEditable, editorModel: SheetEditorModel, itemId: UUID, entry: any EntryDataAccessable, linkTypes: LinkType.Type) {
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
    let entry: any EntryDataAccessable
    let linkTypes: LinkType.Type
    
    @FocusState private var currentFocus: EntryEditorFocusField?
    @Environment(\.appTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    
    @State private var editModel: TextEditModel
    
    var body: some View {
        GlassEffectContainerAll {
            editorCard
        }
        .frame(maxWidth: 800)
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        // Optimization: Combine onChange modifiers to prevent duplicate updates
        .onChange(of: entry.content, initial: true) { _, newContent in
            let source = ItemRowModel(
                itemId: itemId,
                entryId: entry.id,
                typeId: editorModel.module
            )
            // Check if we actually need to update to prevent unnecessary work
            if editModel.source != source ||
                editModel.text != newContent ||
                editModel.name != entry.name {
                updateEditModel(entry: entry, itemId: itemId)
            }
        }
        .onChange(of: entry.name) { _, newName in
            // Only update if name actually changed and content didn't already trigger update
            if editModel.name != newName {
                updateEditModel(entry: entry, itemId: itemId)
            }
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
            try? await Task.sleep(for: .milliseconds(100))
            currentFocus = .name
#endif
        }
    }
    
    private var editorCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            EntryEditorHeaderView(
                editController: editController,
                editorModel: editorModel,
                itemId: itemId,
                editModel: editModel,
                entry: entry,
                linkTypes: linkTypes
            )
            
            EntryNameEditor(editModel: editModel, currentFocus: $currentFocus)
            
            EntryContentEditor(editModel: editModel, currentFocus: $currentFocus)
        }
        .padding(20)
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
    
    private func updateEditModel(entry: any EntryDataAccessable, itemId: UUID) {
        editModel.reset(entry: entry, source: ItemRowModel(itemId: itemId, entryId: entry.id, typeId: editorModel.module))
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
