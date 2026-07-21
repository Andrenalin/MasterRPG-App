// @copyright André Trettin

import CoreRPG
import SwiftUI

struct RuleQuickEntryEditor: View {
    let model: RuleModel

    @Environment(RuleRootModel.self) private var root
    @Environment(\.navigator) private var navigator
    @State private var entries: [RuleEntryModel]
    @State private var affectedEntries: [ItemRowModel] = []
    @State private var showsAffectedLinks = false

    init(model: RuleModel) {
        self.model = model
        _entries = State(initialValue: model.entries)
    }

    var body: some View {
        ManagedNavigationStack(name: "RuleSectionEditor") {
            List {
                ForEach($entries) { $entry in
                    Section {
                        TextField("Title", text: $entry.name)
#if os(tvOS)
                        TextField("Content", text: $entry.content)
#else
                        TextEditor(text: $entry.content)
#endif
                        Picker("Section", selection: $entry.kind) {
                            ForEach(RuleEntryKind.allCases, id: \.self) { kind in
                                Text(kind.localizedTitle).tag(kind)
                            }
                        }
                    } header: {
                        Text(entry.name.isEmpty ? "Untitled Section" : entry.name)
                    }
                }
                .onDelete { entries.remove(atOffsets: $0) }
                .onMove { entries.move(fromOffsets: $0, toOffset: $1) }
            }
            .navigationTitle(model.name)
            .navigationBarTitleDisplayModeAll(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) {
                        navigator.dismiss()
                    } label: {
                        Label("Cancel", systemImage: "xmark")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Add Section", systemImage: "plus") {
                        entries.append(.empty)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", systemImage: "checkmark") {
                        let removedEntries = root.editController.merge(
                            itemId: model.id,
                            entries: entries,
                            recoverEntries: nil
                        )
                        if removedEntries.isEmpty {
                            finishSaving()
                        } else {
                            affectedEntries = removedEntries
                            root.removeEntryListModel.removeItems = removedEntries
                            showsAffectedLinks = true
                        }
                    }
                }
            }
        }
        .sizedSheet(
            isPresented: $showsAffectedLinks,
            idealSize: CGSize(width: 400, height: 600)
        ) {
            EffectedLinkActionPanelView(root: root.rootController, overwrite: true) { removed in
                affectedEntries.removeAll(where: { removed.contains($0) })
                _ = root.editController.merge(
                    itemId: model.id,
                    entries: entries,
                    recoverEntries: affectedEntries
                )
                finishSaving()
            }
        }
    }

    private func finishSaving() {
        root.editController.editorModel.hasChangedEntries += 1
        root.editController.editorModel.sheetRootModel?.updateParent()
        navigator.dismiss()
    }
}

#Preview(traits: .mockData) {
    RuleQuickEntryEditor(model: .preview)
}
