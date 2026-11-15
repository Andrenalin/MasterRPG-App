// @copyright André Trettin

import SwiftUI
import TipKit

public struct EditorLinkView: View {
    public init(root: ItemRootController, model: any ItemDataAccessible, editorLinkModel: EditorLinkModel, selectedModule: NetworkModules? = nil, selectedEntryId: UUID? = nil, destinationModule: NetworkModules? = nil) {
        self.root = root
        self.model = model
        self.editorLinkModel = editorLinkModel
        self.selectedEntryId = selectedEntryId
        self.destinationModule = destinationModule
        self.selectedModule = selectedModule
    }

    let root: ItemRootController
    let model: any ItemDataAccessible
    let editorLinkModel: EditorLinkModel
    let selectedEntryId: UUID?
    let destinationModule: NetworkModules?
    /// Applied in `onAppear`: `init` runs on every parent pass and must not write the model.
    /// See CODE_AUDIT_26 §8.10.
    let selectedModule: NetworkModules?
    
    public var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        
        VStack {
#if os(tvOS)
            if selectionMode {
                TipView(MasterRPGTips.linkContent)
            }
#endif
            PickerAllView(editorLinkModel: editorLinkModel)

            ManagedNavigationStack(name: "EditorLink") {
                EditorLinkListView(editorLinkModel: editorLinkModel, selectionMode: selectionMode)
            }
            .id(editorLinkModel.selection)
            .frame(maxWidth: .infinity, alignment: .top)
            .transition(.opacity)
        }
#if !os(tvOS)
        .popoverTip(selectionMode ? MasterRPGTips.linkContent : nil)
#endif
        .applyIf(selectionMode) {
            $0
                .toolbarItemListModifier(root: root, listControllable: editorLinkModel.folderListController, parentModel: nil, modal: true) {
                    let resolvedRoot = destinationModule.flatMap { editorLinkModel.rootManager?.itemRootController(for: $0) } ?? root
                    guard let editControllable = resolvedRoot.editControllable as? (any EntryDataEditable) else { return }
                    editorLinkModel.addLinkAndReset(editController: editControllable, destinationItemId: model.id, destinationEntryId: selectedEntryId)
                    if let selectedEntryId {
                        editControllable.editorModel.finishLinkSelection(itemId: model.id, entryId: selectedEntryId)
                    }
                }
                .searchItemList(listControllable: editorLinkModel.folderListController)
        }
        .environment(editorLinkModel.folderListController.cacheListItemModel)
        .onChange(of: editorLinkModel.selectionFirstRow) {
            guard let selectionFirstRow = editorLinkModel.selectionFirstRow else { return }
            withAnimation {
                editorLinkModel.update(selection: selectionFirstRow)
            }
        }
        .onChange(of: editorLinkModel.selectionSecondRow) {
            guard let selectionSecondRow = editorLinkModel.selectionSecondRow else { return }
            withAnimation {
                editorLinkModel.update(selection: selectionSecondRow)
            }
        }
        .onChange(of: editorLinkModel.selection, initial: true) { oldValue, newValue in
            if oldValue != newValue {
                editorLinkModel.updateListController()
            }
        }
        .onChange(of: editorLinkModel.folderListController.listDisplayModel.displayMode) { _, _ in
            editorLinkModel.update()
        }
        .onChange(of: editorLinkModel.folderListController.listDisplayModel.listMode) { oldValue, newValue in
            guard oldValue != newValue else { return }
            editorLinkModel.update()
        }
        .onChange(of: editorLinkModel.folderListController.searchModel.searchText) { _, _ in
            editorLinkModel.update()
        }
        .onAppear {
            editorLinkModel.preselectedModule = selectedModule
            guard let preselectedModule = editorLinkModel.preselectedModule else { return }
            withAnimation { editorLinkModel.update(selection: preselectedModule) }
        }
        .navigationTitle(editorLinkModel.selection.title)
        .navigationBarTitleDisplayModeAll(.inline)
    }
}

private extension EditorLinkView {
    var selectionMode: Bool {
        selectedEntryId != nil
    }
}

/// The list of the selected module, as its own view so the picker above does not re-evaluate
/// it. See CODE_AUDIT_26 §8.9.
private struct EditorLinkListView: View {
    let editorLinkModel: EditorLinkModel
    let selectionMode: Bool

    var body: some View {
        let module = editorLinkModel.selection
        if let itemRootController = editorLinkModel.rootManager?.itemRootController(for: module) {
            itemRootController.viewControllable.linkListView(rootController: itemRootController, type: selectionMode ? .selectionInline : .inspector, itemSelectionModel: editorLinkModel.selectionModel(for: module))
        }
    }
}

private struct PickerAllView: View {
    let editorLinkModel: EditorLinkModel

    var body: some View {
        @Bindable var editorLinkModel = editorLinkModel

        ModulePickerRow(selection: $editorLinkModel.selectionFirstRow, modules: editorLinkModel.firstRow)
        if !editorLinkModel.secondRow.isEmpty {
            ModulePickerRow(selection: $editorLinkModel.selectionSecondRow, modules: editorLinkModel.secondRow)
        }
    }
}

private struct ModulePickerRow: View {
    @Binding var selection: NetworkModules?
    let modules: [NetworkModules]

    var body: some View {
        Picker(selection: $selection) {
            ForEach(modules, id: \.self) { module in
                ModulePickerSegment(module: module)
            }
        } label: {
            Text("Module selection", bundle: .module)
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .padding(.horizontal)
    }
}

private struct ModulePickerSegment: View {
    let module: NetworkModules

    var body: some View {
        // Icon-only segment: VoiceOver needs the module name. See CODE_AUDIT_17 §8.3.
        Image(systemName: module.icon)
            .accessibilityLabel(module.title)
            .tag(module)
    }
}

#Preview {
    let fixture = FakeItemRootControllerFixture()
    EditorLinkView(
        root: fixture.root,
        model: FakeItemModel.empty,
        editorLinkModel: EditorLinkModel(
            folderListController: fixture.folderListController,
            firstRow: [.none],
            selection: .none
        )
    )
}
