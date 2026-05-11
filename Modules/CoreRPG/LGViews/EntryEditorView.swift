// @copyright André Trettin

import Foundation
import SwiftUI

public struct EntryEditorView<LinkType: LinkDataTransferable>: View {
    public init(rootManager: RootManager, editorModel: SheetEditorModel, linkTypes: LinkType.Type) {
        self.rootManager = rootManager
        self.editorModel = editorModel
        self.linkTypes = linkTypes
        let editController = rootManager.itemRootController(for: editorModel.module)?.editControllable as? (any EntryDataEditable)
        self._editModel = State(wrappedValue: TextEditModel(linkRegisterController: editController?.linkRegisterController))
    }

    let rootManager: RootManager
    let editorModel: SheetEditorModel
    let linkTypes: LinkType.Type

    @FocusState private var currentFocus: EntryEditorFocusField?
    @State private var editModel: TextEditModel
    @State private var isDropTargeted: Bool = false

    public var body: some View {
        Group {
            if isActive, let itemId = editorModel.itemId {
                content(entry: entry)
                    .id(itemId)
                    .onChange(of: entry.content, initial: true) {
                        editModel.reset(entry: entry, source: ItemRowModel(itemId: itemId, entryId: entry.id, typeId: editorModel.module))
                    }
                    .onChange(of: entry.name) {
                        editModel.reset(entry: entry, source: ItemRowModel(itemId: itemId, entryId: entry.id, typeId: editorModel.module))
                    }
            }
        }
        .transition(.scale)
        .animation(.bouncy, value: isActive)
        .onChange(of: isActive) {
            guard isActive else { return }
            currentFocus = .name
        }
    }

    func content(entry: any EntryDataAccessable) -> some View {
        VStack {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Button {
                            withAnimation { editorModel.entryId = nil }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.headline)
                        }
                        .padding()
#if !os(visionOS)
                        .glassEffectAll(.regular.interactive())
#endif
                        Spacer()

                        Button {
                            save()
                        } label: {
                            Image(systemName: "checkmark")
                                .font(.headline)
                        }
                        .padding()
#if !os(visionOS)
                        .glassEffectAll(.regular.interactive())
#endif
                    }
                    .buttonStyle(.borderless)

                    EntryNameEditor(editModel: editModel, currentFocus: $currentFocus)

                    EntryContentEditor(editModel: editModel, currentFocus: $currentFocus)

                    // Drop Links Button Disable
                }
                .padding()
                .background {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color.accentColor.opacity(0.95).gradient)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .containerShape(.rect(cornerRadius: 24, style: .continuous))
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .padding(32)
        }
        .contentShape(.rect)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var activeEditController: any EntryDataEditable {
        rootManager.itemRootController(for: editorModel.module)?.editControllable as! (any EntryDataEditable)
    }

    var backGroundColor: Color {
        activeEditController.itemControllable.config.module.color
    }

    var isActive: Bool {
#if os(iOS)
        guard !(rootManager.itemRootController(for: editorModel.module)?.editControllable.editorModel.deactivateEntryEditor ?? false) else { return false }
#endif
        return editorModel.entryId != nil
    }

    var entry: any EntryDataAccessable {
        activeEditController.itemControllable.itemOrEmpty(for: editorModel.itemId ?? UUID())[editorModel.entryId ?? UUID()]
    }

    func save() {
        editModel.resetText()
        withAnimation {
            if let itemId = editorModel.itemId {
                activeEditController.update(itemId: itemId, entryId: entry.id, name: editModel.name, content: editModel.text)
            }
            editorModel.entryId = nil
        }
    }

    var dropBackgroundColor: Color {
#if os(iOS) || os(visionOS)
        isDropTargeted ? Color.accentColor : Color(.systemGray6)
#elseif os(tvOS)
        isDropTargeted ? Color.accentColor : .clear
#else
        isDropTargeted ? Color.accentColor : Color(.controlBackgroundColor)
#endif
    }

    @ViewBuilder
    var dropLinkButton: some View {
#if !os(tvOS)
        Text("Drop Links", bundle: .module)
            .padding()
            .background {
                RoundedRectangle(cornerRadius: 24, style: .continuous).fill(dropBackgroundColor)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(isDropTargeted ? Color.accentColor : .clear, lineWidth: 2)
            )
            .dropDestination(for: linkTypes) { items, dropSession in
                isDropTargeted = dropSession.phase == .entering
                editModel.resetText()
                if let itemId = editorModel.itemId {
                    activeEditController.update(itemId: itemId, entryId: entry.id, name: editModel.name, content: editModel.text)
                    items.forEach {
                        activeEditController.add(link: $0.name, module: $0.module, itemId: $0.itemId, entryId: $0.entryId, destinationItemId: itemId, destinationEntryId: entry.id)
                    }
                }
            }
#endif
    }
}

enum EntryEditorFocusField {
    case name
    case information
}

struct EntryNameEditor: View {
    let editModel: TextEditModel
    @FocusState.Binding var currentFocus: EntryEditorFocusField?

    var body: some View {
        @Bindable var editModel = editModel

        Text("Name", bundle: .module)
            .font(.caption)
            .frame(maxWidth: .infinity, alignment: .leading)

        HStack {
            TextField(text: $editModel.name, prompt: Text("Enter a name", bundle: .module)) {
                Text("Name", bundle: .module)
            }
            .focused($currentFocus, equals: .name)
            .labelsHidden()
            .textFieldStyle(.plain)

            Button {
                withAnimation { editModel.name = "" }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .opacity(editModel.name.isEmpty ? 0: 1)
            .contentTransition(.symbolEffect(.automatic))
        }
        .padding(6)
#if os(iOS) || os(visionOS)
        .background(Color(.systemGray6))
#elseif os(tvOS)
        .background(Color(.black))
#else
        .background(Color(.controlBackgroundColor))
#endif
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.secondary, lineWidth: 1)
        }
    }
}

struct EntryContentEditor: View {
    let editModel: TextEditModel
    @FocusState.Binding var currentFocus: EntryEditorFocusField?

    var body: some View {
        Text("Description", bundle: .module)
            .font(.caption)

#if os(tvOS)
        @Bindable var editModel = editModel

        TextField(text: $editModel.text, prompt: Text("Add content", bundle: .module), axis: .vertical) {
            Text("Description", bundle: .module)
        }
        .frame(minHeight: 120, maxHeight: 200)
        .border(Color.accentColor.secondary)
        .padding(.bottom, 6)
        .focused($currentFocus, equals: .information)
#else
        TextEditorLinkView(model: editModel)
            .focused($currentFocus, equals: .information)
            .onChange(of: editModel.attributedText) {
                editModel.updateLinks()
            }
#endif
    }
}

//#Preview {
//    EntryEditRow(editController: FakeEditController.fake, itemId: UUID(), entry: FakeEntryModel.empty, cacheItemListModel: CacheItemListModel())
//}
