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
            List {
                ForEach(entries) { entry in
                    RuleQuickEntrySectionEditor(
                        entryId: entry.id,
                        entries: $entries
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
            AffectedLinkActionPanelView(root: root.rootController, overwrite: true) { removed in
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

    private func addEntry(kind: RuleEntryKind) {
        var entry = RuleEntryModel.empty
        entry.kind = kind
        entries.append(entry)
    }

    private func removeEntries(at offsets: IndexSet) {
        entries = RuleEntryTree.removingEntries(at: offsets, from: entries)
    }

    private func finishSaving() {
        root.editController.editorModel.hasChangedEntries += 1
        root.editController.editorModel.sheetRootModel?.updateParent()
        navigator.dismiss()
    }
}

private struct RuleQuickEntrySectionEditor: View {
    let entryId: UUID
    @Binding var entries: [RuleEntryModel]

    var body: some View {
        if let index = entries.firstIndex(where: { $0.id == entryId }) {
            let entry = $entries[index]
            let parentGroups = RuleEntryTree.validParentGroups(
                for: entryId,
                in: entries
            )

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
                Label(
                    entry.wrappedValue.name.isEmpty
                        ? "Untitled Section"
                        : entry.wrappedValue.name,
                    systemImage: entry.wrappedValue.kind == .group ? "folder" : "doc.text"
                )
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
