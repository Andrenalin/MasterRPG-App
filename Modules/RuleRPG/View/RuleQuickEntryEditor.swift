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
        _entries = State(initialValue: RuleEntryTree.normalized(model.entries))
    }

    var body: some View {
        ManagedNavigationStack(name: "RuleSectionEditor") {
            // Built once for all rows; see `RuleEntryTree.ParentGroupLookup`.
            let lookup = RuleEntryTree.ParentGroupLookup(entries: entries)
            List {
                ForEach(entries) { entry in
                    RuleQuickEntrySectionEditor(
                        entryId: entry.id,
                        entries: $entries,
                        lookup: lookup
                    )
                }
                .onDelete(perform: removeEntries)
                .onMove { entries.move(fromOffsets: $0, toOffset: $1) }
            }
            .navigationTitle(model.name)
            .navigationBarTitleDisplayModeAll(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) {
                        navigator.dismiss()
                    } label: {
                        Label(
                            String(localized: "Cancel", bundle: .ruleModule),
                            systemImage: "xmark"
                        )
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            addEntry(kind: .text)
                        } label: {
                            Label {
                                Text("Add Section", bundle: .ruleModule)
                            } icon: {
                                Image(systemName: "doc.text")
                            }
                        }
                        Button {
                            addEntry(kind: .group)
                        } label: {
                            Label {
                                Text("Add Group", bundle: .ruleModule)
                            } icon: {
                                Image(systemName: "folder")
                            }
                        }
                    } label: {
                        Label {
                            Text("Add", bundle: .ruleModule)
                        } icon: {
                            Image(systemName: "plus")
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(
                        String(localized: "Save", bundle: .ruleModule),
                        systemImage: "checkmark"
                    ) {
                        entries = RuleEntryTree.normalized(entries)
                        // The editor persists also during a game, like QuickEntryEditorView.
                        let removedEntries = root.editController.merge(
                            itemId: model.id,
                            entries: entries,
                            recoverEntries: nil,
                            forceSave: true
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
            idealSize: .panelSheet
        ) {
            AffectedLinkActionPanelView(root: root.rootController, overwrite: true) { removed in
                affectedEntries.removeAll(where: { removed.contains($0) })
                _ = root.editController.merge(
                    itemId: model.id,
                    entries: entries,
                    recoverEntries: affectedEntries,
                    forceSave: true
                )
                finishSaving()
            }
        }
    }

    private func addEntry(kind: RuleEntryKind) {
        var entry = RuleEntryModel.empty
        entry.kind = kind
        entries.append(entry)
    }

    private func removeEntries(at offsets: IndexSet) {
        entries = RuleEntryTree.removingEntries(at: offsets, from: entries)
    }

    private func finishSaving() {
        root.editController.editorModel.sheetRootModel?.updateParent()
        navigator.dismiss()
    }
}

private struct RuleQuickEntrySectionEditor: View {
    let entryId: UUID
    @Binding var entries: [RuleEntryModel]
    let lookup: RuleEntryTree.ParentGroupLookup

    var body: some View {
        if let index = lookup.index(of: entryId), entries.indices.contains(index) {
            let entry = $entries[index]
            let parentGroups = lookup.validParentGroups(for: entryId)

            Section {
                TextField(
                    String(localized: "Title", bundle: .ruleModule),
                    text: entry.name
                )
                if entry.wrappedValue.kind != .group {
#if os(tvOS)
                    TextField(
                        String(localized: "Content", bundle: .ruleModule),
                        text: entry.content
                    )
#else
                    TextEditor(text: entry.content)
#endif
                }
                Picker(
                    String(localized: "Section", bundle: .ruleModule),
                    selection: kindSelection
                ) {
                    ForEach(RuleEntryKind.allCases, id: \.self) { kind in
                        Text(kind.localizedTitle).tag(kind)
                    }
                }
                Picker(selection: parentSelection) {
                    Text("Top Level", bundle: .ruleModule).tag(UUID?.none)
                    ForEach(parentGroups) { group in
                        Text(
                            group.name.isEmpty
                                ? String(localized: "Untitled Group", bundle: .ruleModule)
                                : group.name
                        )
                            .tag(Optional(group.id))
                    }
                } label: {
                    Text("Parent Group", bundle: .ruleModule)
                }
            } header: {
                Label {
                    if entry.wrappedValue.name.isEmpty {
                        Text("Untitled Section", bundle: .ruleModule)
                    } else {
                        Text(verbatim: entry.wrappedValue.name)
                    }
                } icon: {
                    Image(systemName: entry.wrappedValue.kind == .group ? "folder" : "doc.text")
                }
            }
        }
    }

    private var kindSelection: Binding<RuleEntryKind> {
        Binding(
            get: {
                entries.first(where: { $0.id == entryId })?.kind ?? .text
            },
            set: { kind in
                entries = RuleEntryTree.settingKind(
                    kind,
                    for: entryId,
                    in: entries
                )
            }
        )
    }

    private var parentSelection: Binding<UUID?> {
        Binding(
            get: {
                entries.first(where: { $0.id == entryId })?.parentId
            },
            set: { parentId in
                entries = RuleEntryTree.settingParent(
                    parentId,
                    for: entryId,
                    in: entries
                )
            }
        )
    }
}

#Preview(traits: .mockData) {
    RuleQuickEntryEditor(model: .preview)
}
