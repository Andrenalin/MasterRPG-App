// @copyright André Trettin

import SwiftUI

struct EntryEditorHeaderView<LinkType: LinkDataTransferable>: View {
    let editController: any EntryDataEditable
    let editorModel: SheetEditorModel
    let itemId: UUID
    @Bindable var editModel: TextEditModel
    let entry: any EntryDataAccessable
    let linkTypes: LinkType.Type
    
    @State private var isDropTargeted: Bool = false
    @State private var isSaving: Bool = false
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack(spacing: 12) {
            dismissButton

            dropLinkArea

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
            Image(systemName: "xmark")
        }
        .padding(12)
        .foregroundStyle(.primary)
#if os(macOS)
        .keyboardShortcut(.cancelAction)
#endif
#if !os(visionOS)
        .glassEffectAll(.regular.interactive())
#endif
        .accessibilityLabel(Text("Close editor", bundle: .module))
    }
    
    // MARK: - Save Button
    
    private var saveButton: some View {
        Button(action: save) {
            Image(systemName: "checkmark")
        }
        .padding(12)
        .foregroundStyle(.primary)
#if !os(visionOS)
        .glassEffectAll(.regular.interactive())
#endif
        .accessibilityLabel(Text("Save entry", bundle: .module))
    }
    
    func save() {
#if os(iOS)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
#endif
        
        editModel.resetText()
        
        editController.update(
            itemId: itemId,
            entryId: entry.id,
            name: editModel.name,
            content: editModel.text
        )
        
        withAnimation { editorModel.entryId = nil }
    }
    
    // MARK: - Drop Link Button
    
    @ViewBuilder private var dropLinkArea: some View {
#if !os(tvOS)
        Label {
            Text("Drop Links", bundle: .module)
        } icon: {
            Image(systemName: "square.and.arrow.down")
                .imageScale(.large)
        }
        .font(.caption)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .center)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(dropBackgroundColor)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(dropStrokeColor, lineWidth: 2)
        }
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .scaleEffect(isDropTargeted ? 1.1 : 1.0)
        .dropDestination(for: linkTypes) { items, location in
            handleDrop(items: items)
            return true
        } isTargeted: { isTargeted in
            withAnimation(.snappy(duration: 0.2)) {
                isDropTargeted = isTargeted
            }
        }
        .accessibilityLabel(Text("Drop links area", bundle: .module))
        .accessibilityHint(Text("Drag and drop links here to add them to this entry", bundle: .module))
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
        // Enhancement 3: Add haptic feedback on drop
#if os(iOS)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
#endif
        
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
        
        // Enhancement 3: Success haptic after drop
#if os(iOS)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
#endif
    }
}

#Preview {
    @Previewable var editModel = TextEditModel(linkRegisterController: LinkRegisterController.fake)
    EntryEditorHeaderView(
        editController: FakeEditController.fake,
        editorModel: SheetEditorModel(),
        itemId: UUID(),
        editModel: editModel,
        entry: FakeEntryModel.empty,
        linkTypes: EmptyLinkTransferable.self
    )
}
