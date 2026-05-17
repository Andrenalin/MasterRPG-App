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
    @Environment(\.colorScheme) private var colorScheme

    @State private var editModel: TextEditModel

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                Spacer()
                
                editorCard
                    .frame(maxWidth: min(geometry.size.width - 64, 800))
                    .frame(maxHeight: min(geometry.size.height - 64, 600))
                
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Optimization: Combine onChange modifiers to prevent duplicate updates
            .onChange(of: entry.content, initial: true) { _, newContent in
                // Check if we actually need to update to prevent unnecessary work
                if editModel.text != newContent || editModel.name != entry.name {
                    updateEditModel(entry: entry, itemId: itemId)
                }
            }
            .onChange(of: entry.name) { _, newName in
                // Only update if name actually changed and content didn't already trigger update
                if editModel.name != newName {
                    updateEditModel(entry: entry, itemId: itemId)
                }
            }
        }
        .background {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    // Dismiss on background tap
                    withAnimation {
                        editorModel.entryId = nil
                    }
                }
        }
        .task {
            // Small delay to ensure smooth appearance
            try? await Task.sleep(for: .milliseconds(100))
            currentFocus = .name
        }
    }
    
    private var editorCard: some View {
        VStack(alignment: .leading, spacing: 12) {
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
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(adaptiveCardBackground)
                .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
        }
        .containerShape(.rect(cornerRadius: 24, style: .continuous))
    }
    
    private var adaptiveCardBackground: some ShapeStyle {
        if colorScheme == .dark {
            return Color.accentColor.opacity(0.9).gradient
        } else {
            return Color.accentColor.opacity(0.95).gradient
        }
    }
    
    private func updateEditModel(entry: any EntryDataAccessable, itemId: UUID) {
        editModel.reset(entry: entry, source: ItemRowModel(itemId: itemId, entryId: entry.id, typeId: editorModel.module))
    }
}

enum EntryEditorFocusField {
    case name
    case information
}
