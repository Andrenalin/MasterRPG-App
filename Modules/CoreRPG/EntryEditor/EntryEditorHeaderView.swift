// @copyright André Trettin

import SwiftUI

struct EntryEditorHeaderView<LinkType: LinkDataTransferable>: View {
    let editController: any EntryDataEditable
    let editorModel: SheetEditorModel
    let itemId: UUID
    let editModel: TextEditModel
    let entry: any EntryDataAccessable
    let linkTypes: LinkType.Type
    
    @State private var isDropTargeted: Bool = false
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack(spacing: 12) {
            dismissButton
            
            Spacer()
            
            dropLinkButton
            
            Spacer()
            
            saveButton
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 8)
    }
    
    // MARK: - Dismiss Button
    
    private var dismissButton: some View {
        Button {
            withAnimation { editorModel.entryId = nil }
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
        }
        .padding(12)
#if !os(visionOS)
        .glassEffectAll(.regular.interactive())
#endif
        .accessibilityLabel("Close editor")
    }
    
    // MARK: - Save Button
    
    private var saveButton: some View {
        Button(action: save) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
        }
        .padding(12)
#if !os(visionOS)
        .glassEffectAll(.regular.interactive())
#endif
        .accessibilityLabel("Save entry")
    }
    
    func save() {
        editModel.resetText()
        withAnimation {
            if let itemId = editorModel.itemId {
                editController.update(itemId: itemId, entryId: entry.id, name: editModel.name, content: editModel.text)
            }
            editorModel.entryId = nil
        }
    }
    
    // MARK: - Drop Link Button
    
    private var dropLinkButton: some View {
#if !os(tvOS)
        Text("Drop Links", bundle: .module)
            .font(.subheadline)
            .fontWeight(.medium)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(dropBackgroundColor)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(dropStrokeColor, lineWidth: 2)
            }
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .dropDestination(for: linkTypes) { items, location in
                handleDrop(items: items)
                return true
            } isTargeted: { isTargeted in
                withAnimation(.snappy(duration: 0.2)) {
                    isDropTargeted = isTargeted
                }
            }
            .accessibilityLabel("Drop links area")
            .accessibilityHint("Drag and drop links here to add them to this entry")
#endif
    }
    
    // MARK: - Computed Properties
    
    private var dropBackgroundColor: Color {
#if os(iOS) || os(visionOS)
        if isDropTargeted {
            return Color.accentColor.opacity(0.2)
        }
        return colorScheme == .dark ? Color(uiColor: .systemGray5) : Color(uiColor: .systemGray6)
#elseif os(tvOS)
        return isDropTargeted ? Color.accentColor.opacity(0.3) : .clear
#else
        if isDropTargeted {
            return Color.accentColor.opacity(0.2)
        }
        return Color(nsColor: .controlBackgroundColor)
#endif
    }
    
    private var dropStrokeColor: Color {
        isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.3)
    }
    
    // MARK: - Actions
    
    private func handleDrop(items: [LinkType]) {
        editModel.resetText()
        editController.update(
            itemId: itemId,
            entryId: entry.id,
            name: editModel.name,
            content: editModel.text
        )
        
        items.forEach { link in
            editController.add(
                link: link.name,
                module: link.module,
                itemId: link.itemId,
                entryId: link.entryId,
                destinationItemId: itemId,
                destinationEntryId: entry.id
            )
        }
    }
}
