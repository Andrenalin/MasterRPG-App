// @copyright André Trettin

import SwiftUI

struct EntryEditorHeaderView<LinkType: LinkDataTransferable>: View {
    let editController: any EntryDataEditable
    let editorModel: SheetEditorModel
    let itemId: UUID
    @Bindable var editModel: TextEditModel
    let entry: any EntryDataAccessible
    let linkTypes: LinkType.Type
    
    @State private var isDropTargeted: Bool = false
    @State private var isSaving: Bool = false
    @Environment(\.appTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    
    var body: some View {
        GlassEffectContainerAll {
            HStack(spacing: 12) {
                EntryEditorHeaderDismissButtonView(editorModel: editorModel)

                EntryEditorHeaderDropLinkAreaView(linkTypes: linkTypes, dropBackgroundColor: dropBackgroundColor, dropStrokeColor: dropStrokeColor, isDropTargeted: $isDropTargeted, handleDrop: handleDrop)

                EntryEditorHeaderSaveButtonView(isSaving: isSaving, save: save)
            }
        }
    }

    func save() {
        guard !isSaving else { return }
        isSaving = true
#if os(iOS)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
#endif
        
        editModel.resetNameText()
        editModel.resetText()

        editController.update(
            itemId: itemId,
            entryId: entry.id,
            name: editModel.name,
            content: editModel.text,
            // The standalone item editor always persists, even while a game is
            // running — unlike in-game quick-edit surfaces, which stay memory-only.
            forceSave: true
        )

        withAnimation(accessibilityReduceMotion ? nil : .default) { editorModel.entryId = nil }
    }
    
    // MARK: - Computed Properties
    
    private var dropBackgroundColor: Color {
        if isDropTargeted {
            return theme.tint(for: editorModel.module).opacity(0.22)
        }
        return theme.panelColor.opacity(0.38)
    }
    
    private var dropStrokeColor: Color {
        isDropTargeted
            ? theme.tint(for: editorModel.module)
            : theme.secondaryForegroundColor.opacity(0.35)
    }
    
    // MARK: - Actions
    
    private func handleDrop(items: [LinkType]) {
        // Enhancement 3: Add haptic feedback on drop
#if os(iOS)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
#endif
        
        editModel.resetNameText()
        editModel.resetText()
        editController.update(
            itemId: itemId,
            entryId: entry.id,
            name: editModel.name,
            content: editModel.text,
            // The standalone item editor always persists, even while a game is
            // running — unlike in-game quick-edit surfaces, which stay memory-only.
            forceSave: true
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
        delayedTask(.settleDelay) {
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

// MARK: - Extracted subviews (CODE_AUDIT §8.3)

private struct EntryEditorHeaderDismissButtonView: View {
    let editorModel: SheetEditorModel
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    var body: some View {
        GlassButton(action: {
            withAnimation(accessibilityReduceMotion ? nil : .default) { editorModel.entryId = nil }
        }) {
            Label {
                Text("Close editor", bundle: .module)
            } icon: {
                Image(systemName: "xmark")
            }
            .labelStyle(.iconOnly)
        }
        .buttonSizing(.fitted)
        .buttonBorderShape(.circle)
        .controlSize(.large)
#if os(macOS)
        .keyboardShortcut(.cancelAction)
#endif
    }
}

private struct EntryEditorHeaderSaveButtonView: View {
    let isSaving: Bool
    let save: () -> Void

    var body: some View {
        GlassButton(isProminent: true, action: save) {
            Label {
                Text("Save entry", bundle: .module)
            } icon: {
                Image(systemName: isSaving ? "ellipsis" : "checkmark")
            }
            .labelStyle(.iconOnly)
        }
        .buttonSizing(.fitted)
        .buttonBorderShape(.circle)
        .controlSize(.large)
        .disabled(isSaving)
    }
}

private struct EntryEditorHeaderDropLinkAreaView<LinkType: LinkDataTransferable>: View {
    let linkTypes: LinkType.Type
    let dropBackgroundColor: Color
    let dropStrokeColor: Color
    @Binding var isDropTargeted: Bool
    let handleDrop: ([LinkType]) -> Void

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    @ViewBuilder var body: some View {
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
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(dropBackgroundColor)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(dropStrokeColor, lineWidth: isDropTargeted ? 2 : 1)
        }
        .contentShape(.rect(cornerRadius: 16, style: .continuous))
        .scaleEffect(isDropTargeted ? 1.03 : 1)
        .dropDestination(for: linkTypes) { items, _ in
            handleDrop(items)
            return true
        } isTargeted: { isTargeted in
            withAnimation(accessibilityReduceMotion ? nil : .snappy(duration: 0.2)) {
                isDropTargeted = isTargeted
            }
        }
        .accessibilityLabel(Text("Drop links area", bundle: .module))
        .accessibilityHint(Text("Drag and drop links here to add them to this entry", bundle: .module))
#endif
    }
}
