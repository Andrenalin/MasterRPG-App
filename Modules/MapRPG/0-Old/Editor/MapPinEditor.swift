// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import SwiftUI

struct MapPinEditor: View {
    let root: MapRootModel
    let editController: EditController

#if !os(tvOS)
    @Environment(\.openWindow) private var openWindow
#endif

    @State private var expandedEntries: [UUID: Bool] = [:]
    @State private var selected = Set<UUID>()
    @State private var selection = [UUID]()
    @State private var showDeleteAlert: Bool = false

    func expandedEntry(entryId: UUID) -> Binding<Bool> {
        Binding {
            expandedEntries[entryId, default: false]
        } set: {
            expandedEntries[entryId] = $0
        }
    }

    var body: some View {
        @Bindable var model = editController.model
        VStack {
            actionBarView

            Table(model.mapPins, selection: $selected) {
                TableColumn(Text("Name", bundle: .module)) { pin in
                    DisclosureGroupTV(isExpanded: expandedEntry(entryId: pin.id)) {
                        TextFieldInlineEditor(editController: editController, model: $model[MapPinId.id, pin.id].name, prompt: "Enter a name for the pin", bundle: .module)
                    } label: {
                        Text(pin.name)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .contextMenu {
                                contextMenuView(pin: pin, keyPath: \.name)
                            }
                    }
                }
                .width(min: 32, ideal: 128)

                TableColumn(Text("Shown", bundle: .module)) { pin in
                    ToggleEditor(editController: editController, model: $model[MapPinId.id, pin.id].isShown, bundle: .module)
                        .labelsHidden()
                        .labelsHidden()
                }
                .width(42)

                TableColumn(Text("Size", bundle: .module)) { pin in
                    ValuePickerEditor(editController: editController, model: $model[MapPinId.id, pin.id].size, allCategories: MapPinModel.MapPinSize.allCases, title: "Size", bundle: .module) { size in
                        Text(size.text)
                    }
                    .labelsHidden()
                }
                .width(120)

                TableColumn(Text("Image", bundle: .module)) { pin in
                    PinImageDropArea(root: root, editController: editController, pin: pin)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .width(128)
            }
#if os(macOS)
            .tableStyle(.bordered(alternatesRowBackgrounds: true))
            .onDeleteCommand {
                withAnimation { showDeleteAlert.toggle() }
            }
            .onMoveCommand { direction in
                guard selected.count == 1 && (direction == .left || direction == .right) else { return }
                guard let pinId = selected.first else { return }
                editController.move(pinId: pinId, up: direction == .left)
            }
#endif
            .onChange(of: selected, initial: true) {
                withAnimation { syncSelection(with: selected) }
            }
            .onChange(of: selection, initial: true) {
                guard let entryId = selection.last else { return }
                withAnimation { editController.editorModel.currentSecondaryId = entryId }
                if expandedEntries[entryId, default: false] == false {
                    withAnimation {
                        expandedEntries = [:]
                        expandedEntries[entryId] = true
                    }
                }
            }
            .alert(Text("Remove Entries", bundle: .module), isPresented: $showDeleteAlert) {
                Button(role: .destructive) {
                    withAnimation { selected.forEach { editController.remove(pinId: $0) } }
                } label: {
                    Text("Remove", bundle: .module)
                }
            } message: {
                Text(removingTitles)
            }
        }
    }

    private var removingTitles: String {
        "Do you really want to remove:\n" +
        selection.compactMap {
            guard let item = root.itemController.itemSync(for: editController.model.id) else { return nil }
            return item[MapPinId.id, $0].name
        }.joined(separator: "\n")
    }

    private func syncSelection(with newSelected: Set<MapPinModel.ID>) {
        let existingSelected = newSelected.filter { selectedId in
            editController.model.mapPins.contains { $0.id == selectedId }
        }
        var newSelection = selection.filter { existingSelected.contains($0) }
        var diffSelection = Array(existingSelected.filter { !newSelection.contains($0) })
        diffSelection.sort { a, b in
            guard let itemA = editController.model.mapPins.firstIndex(where: { $0.id == a }),
                  let itemB = editController.model.mapPins.firstIndex(where: { $0.id == b }) else { return false }
            return itemA < itemB
        }
        newSelection.append(contentsOf: diffSelection)
        selection <=> newSelection
        selected <=> existingSelected
    }

    @ViewBuilder
    private func contextMenuView(pin: MapPinModel, keyPath: KeyPath<MapPinModel, String>) -> some View {
        Button {
            withAnimation { editController.copy(pinIds: selection.isEmpty ? [pin.id] : selection) }
        } label: {
            if selection.count > 0 {
                Text("Copy \(selection.count) entry", bundle: .module)
            } else {
                Text("Copy row \(pinName(for: pin))", bundle: .module)
            }
        }

        Divider()
        Button(role: .destructive) {
            withAnimation { editController.remove(pinIds: selection.isEmpty ? [pin.id] : selection) }
        } label: {
            Label { Text(pinName(for: pin, selection: selection), bundle: .module) } icon: { Image(systemName: "trash") }
                .foregroundStyle(.red)
        }
        .keyboardShortcut(KeyEquivalent.delete, modifiers: [])
    }

    private func pinName(for pin: MapPinModel, selection: [UUID]) -> LocalizedStringKey {
        selection.count > 0 ? "Delete \(selection.count) Pin" : "Delete row \(pinName(for: pin))"
    }
    
    private func pinName(for pin: MapPinModel) -> String {
        String(pin.name.prefix(16))
    }

    private var actionBarView: some View {
        HStack {
            Button {
                withAnimation {
                    let entryId = editController.addNewPin()
                    expandedEntries = [entryId: true]
                }
            } label: {
                Label {
                    Text("Add", bundle: .module)
                } icon: {
                    Image(systemName: "plus")
                }
            }

            Text("\(editController.model.mapPins.count) Pin", bundle: .module)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .center)

            Button {
                withAnimation {
#if !os(tvOS)
                    openWindow(id: NetworkModules.photo.linkWindowId)
#endif
                }
            } label: {
                Image(systemName: NetworkModules.photo.icon)
            }

            Button {
                withAnimation {
#if !os(tvOS)
                    openWindow(id: NetworkModules.value.linkWindowId)
#endif
                }
            } label: {
                Image(systemName: NetworkModules.value.icon)
            }

            PinDropArea(root: root, editController: editController)
        }
    }
}

#endif
