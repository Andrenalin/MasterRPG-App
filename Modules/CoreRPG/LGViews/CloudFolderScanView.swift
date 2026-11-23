// @copyright André Trettin

import SwiftUI

/// Compares the module's iCloud folder with its items and lists what differs. The user sees what
/// would change, deselects what should stay as it is, and applies the rest.
struct CloudFolderScanView: View {
    let root: any ItemRootControllable

    @Environment(\.navigator) private var navigator
    @State private var model = CloudFolderScanModel()

    private var controller: CloudScanController {
        CloudScanController(itemController: root.itemControllable, editController: root.editControllable)
    }

    var body: some View {
        ManagedNavigationStack {
            Group {
                switch model.phase {
                case .scanning, .syncing:
                    ProgressView {
                        Text(model.phase == .syncing ? "Syncing…" : "Scanning iCloud folder…", bundle: .module)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .found(let plan):
                    CloudFolderScanPlanList(plan: plan, model: model)
                case .nothingFound:
                    ContentUnavailableView {
                        Label {
                            Text("Everything is in sync", bundle: .module)
                        } icon: {
                            Image(systemName: "checkmark.icloud")
                        }
                    } description: {
                        Text("The items and the files in the iCloud folder match.", bundle: .module)
                    }
                case .unavailable:
                    ContentUnavailableView {
                        Label {
                            Text("No iCloud files", bundle: .module)
                        } icon: {
                            Image(systemName: "icloud.slash")
                        }
                    } description: {
                        Text("This module does not keep files in iCloud.", bundle: .module)
                    }
                case .unreachable:
                    ContentUnavailableView {
                        Label {
                            Text("iCloud folder not available", bundle: .module)
                        } icon: {
                            Image(systemName: "icloud.slash")
                        }
                    } description: {
                        Text("The folder cannot be read. Check that iCloud Drive is on and try again.", bundle: .module)
                    }
                case .synced(let added, let folders, let moved, let trashed):
                    ContentUnavailableView {
                        Label {
                            Text("Synced with iCloud", bundle: .module)
                        } icon: {
                            Image(systemName: "icloud.and.arrow.down")
                        }
                    } description: {
                        Text("Added \(added) items in \(folders) new folders, moved \(moved) items, trashed \(trashed) items.", bundle: .module)
                    }
                case .busy:
                    ContentUnavailableView {
                        Label {
                            Text("Another change is running", bundle: .module)
                        } icon: {
                            Image(systemName: "hourglass")
                        }
                    } description: {
                        Text("Try again when the import or repair has finished.", bundle: .module)
                    }
                }
            }
            .navigationTitle(Text("Sync with iCloud", bundle: .module))
            .frame(minHeight: 300)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        navigator.dismiss()
                    } label: {
                        Text(isFinished ? "Done" : "Cancel", bundle: .module)
                    }
                    // The sync keeps running when the sheet is dismissed, so Cancel is not offered
                    // while it runs. See CODE_AUDIT_28 §8.4.
                    .disabled(isSyncing)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if case .found = model.phase {
                        Button {
                            Task {
                                await model.sync(with: controller)
                                root.folderListControllable.scheduleSearch()
                            }
                        } label: {
                            Text("Sync", bundle: .module)
                        }
                        .disabled(!model.hasSelection)
                    }
                }
            }
        }
        .task {
            await model.scan(with: controller)
        }
    }

    private var isSyncing: Bool {
        if case .syncing = model.phase { true } else { false }
    }

    private var isFinished: Bool {
        switch model.phase {
        case .synced, .nothingFound, .unavailable, .unreachable, .busy: true
        case .scanning, .found, .syncing: false
        }
    }
}

/// The differences, one section per kind. Each row has a checkbox; all are on by default.
struct CloudFolderScanPlanList: View {
    let plan: CloudScanPlan
    let model: CloudFolderScanModel

    var body: some View {
        List {
            if plan.mostFilesMissing {
                Section {
                    Label {
                        Text("Most files are missing. iCloud may still be syncing. Check the list before the items are trashed.", bundle: .module)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }
            }
            if !plan.unreadableFolders.isEmpty {
                Section {
                    Label {
                        Text("Some folders could not be read. Their items were left unchanged.", bundle: .module)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                    ForEach(plan.unreadableFolders, id: \.self) { folder in
                        Text(folder.joined(separator: "/"))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if !plan.items.isEmpty {
                Section {
                    ForEach(plan.items) { item in
                        CloudSyncRow(model: model, id: item.id, systemImage: "doc.badge.plus", title: item.file.components.joined(separator: "/"), detail: nil)
                    }
                } header: {
                    CloudSyncSectionHeader(model: model, title: Text("Files without item", bundle: .module), ids: plan.items.map(\.id))
                }
            }
            if !plan.movedFiles.isEmpty {
                Section {
                    ForEach(plan.movedFiles) { move in
                        CloudSyncRow(model: model, id: move.id, systemImage: "arrow.right.doc.on.clipboard", title: move.name, detail: move.pathChange)
                    }
                } header: {
                    CloudSyncSectionHeader(model: model, title: Text("Files moved on iCloud", bundle: .module), ids: plan.movedFiles.map(\.id))
                }
            }
            if !plan.movedItems.isEmpty {
                Section {
                    ForEach(plan.movedItems) { move in
                        CloudSyncRow(model: model, id: move.id, systemImage: "folder.badge.gearshape", title: move.name, detail: move.pathChange)
                    }
                } header: {
                    CloudSyncSectionHeader(model: model, title: Text("Items in another folder than their file", bundle: .module), ids: plan.movedItems.map(\.id))
                }
            }
            if !plan.removals.isEmpty {
                Section {
                    ForEach(plan.removals) { removal in
                        CloudSyncRow(model: model, id: removal.id, systemImage: "trash", title: removal.name, detail: removal.path.joined(separator: "/"))
                    }
                } header: {
                    CloudSyncSectionHeader(model: model, title: Text("Files missing on iCloud", bundle: .module), ids: plan.removals.map(\.id))
                } footer: {
                    Text("Select the items to move to the trash. Nothing is trashed unless you select it.", bundle: .module)
                }
            }
            // The folders the selected rows need, created when synced.
            let newFolders = model.selectedPlan?.folders ?? []
            if !newFolders.isEmpty {
                Section {
                    ForEach(newFolders) { folder in
                        Label(folder.path.joined(separator: "/"), systemImage: "folder.badge.plus")
                    }
                } header: {
                    Text("New folders", bundle: .module)
                }
            }
        }
    }
}

private extension CloudScanPlan.Move {
    /// "from → to", the root shown as "/".
    var pathChange: String {
        let origin = from.isEmpty ? "/" : from.joined(separator: "/")
        let destination = to.isEmpty ? "/" : to.joined(separator: "/")
        return "\(origin) → \(destination)"
    }
}

/// A section title with a switch that selects or deselects the whole section.
private struct CloudSyncSectionHeader: View {
    let model: CloudFolderScanModel
    let title: Text
    let ids: [UUID]

    var body: some View {
        HStack {
            title
            Spacer()
            Button {
                model.setSelected(!model.areAllSelected(ids), for: ids)
            } label: {
                if model.areAllSelected(ids) {
                    Text("Deselect All", bundle: .module)
                } else {
                    Text("Select All", bundle: .module)
                }
            }
            .buttonStyle(.borderless)
        }
    }
}

/// One entry with its checkbox.
private struct CloudSyncRow: View {
    let model: CloudFolderScanModel
    let id: UUID
    let systemImage: String
    let title: String
    let detail: String?

    var body: some View {
        Button {
            model.toggle(id)
        } label: {
            HStack {
                Image(systemName: model.isSelected(id) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(model.isSelected(id) ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading) {
                    Label(title, systemImage: systemImage)
                    if let detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(model.isSelected(id) ? Text("Selected", bundle: .module) : Text("Not selected", bundle: .module))
    }
}
