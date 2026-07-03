// @copyright André Trettin

import SwiftUI

// MARK: - Shared Sub-Views

private struct IRDecisionBadge: View {
    let decision: SingleReviewDecision
    
    var body: some View {
        Label(decision.rawValue, systemImage: decision.systemImage)
            .font(.caption2)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(decision.tint.opacity(0.15))
            .foregroundStyle(decision.tint)
            .clipShape(.capsule)
    }
}

private struct IRModuleRow: View {
    let module: ImportReviewModule
    
    private var addedCount: Int   { module.reviewItems.filter { $0.kind == .added }.count }
    private var changedCount: Int { module.reviewItems.filter { $0.kind == .different }.count }
    private var blockedCount: Int { module.reviewItems.filter(\.hasBlockingReference).count }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(module.name, systemImage: module.id.icon).bold()
                Spacer()
                Text("\(module.reviewItems.count)").foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                if addedCount > 0 {
                    Label("\(addedCount) new", systemImage: "circle.fill").foregroundStyle(.green)
                }
                if changedCount > 0 {
                    Label("\(changedCount) changed", systemImage: "circle.fill").foregroundStyle(.orange)
                }
                if blockedCount > 0 {
                    Label("\(blockedCount) blocked", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                }
            }
            .font(.caption)
        }
        .padding(.vertical, 4)
    }
}

private struct IRItemListRow: View {
    let item: ImportReviewItemModel
    
    var body: some View {
        HStack {
            Image(systemName: item.kind == .added ? "plus.circle.fill" : "arrow.triangle.2.circlepath.circle.fill")
                .foregroundStyle(item.kind == .added ? .green : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                Text(item.summary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if item.hasBlockingReference {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red).font(.caption)
            }
            IRDecisionBadge(decision: item.itemModel.decision)
        }
        .padding(.vertical, 2)
    }
}

private struct IRStatusGrid: View {
    let item: ImportReviewItemModel
    
    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 0) {
            GridRow {
                IRStatusCell(title: "Existing", value: item.existingStatus, tint: .secondary)
                IRStatusCell(title: "Imported", value: item.importedStatus, tint: .green)
                IRStatusCell(title: "Merged",   value: item.mergedStatus,   tint: .blue)
            }
        }
    }
}

private struct IRStatusCell: View {
    let title: String
    let value: String
    let tint: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption2).foregroundStyle(tint)
            Text(value).font(.caption).lineLimit(3).frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
        .background(.quaternary)
        .clipShape(.rect(cornerRadius: 8))
    }
}

private struct IRReferenceSection: View {
    let item: ImportReviewItemModel
    let onSelect: (SingleReviewReference) -> Void
    
    var body: some View {
        if !item.itemModel.references.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("References").font(.headline)
                ForEach(item.itemModel.references) { ref in
                    IRReferenceRow(ref: ref) { onSelect(ref) }
                }
            }
        }
    }
}

private struct IRReferenceRow: View {
    let ref: SingleReviewReference
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack {
                Image(systemName: ref.status.systemImage).foregroundStyle(ref.status.tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text(ref.itemName)
                    Text(ref.moduleName).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                ref.status.label.font(.caption2).foregroundStyle(ref.status.tint)
            }
            .padding(10)
            .background(ref.status.tint.opacity(0.08))
            .clipShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityHint(ref.isResolved ? "Reference is resolved" : "Navigate to this referenced item")
    }
}

private struct IRPropertySection: View {
    let item: ImportReviewItemModel
    let onDecision: (SingleReviewDecision, UUID) -> Void
    
    var body: some View {
        if !item.itemModel.properties.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Properties").font(.headline)
                ForEach(item.itemModel.properties) { prop in
                    IRPropertyRow(model: item.itemModel, prop: prop) { d in onDecision(d, prop.id) }
                }
            }
        }
    }
}

private struct IRPropertyRow: View {
    let model: SingleItemImportModel
    let prop: SingleReviewItemProperty
    let onDecision: @MainActor (SingleReviewDecision) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(prop.displayName).bold()
                Spacer()
                IRDecisionBadge(decision: prop.decision)
            }
            Grid(horizontalSpacing: 8, verticalSpacing: 4) {
                GridRow {
                    Text("Existing").font(.caption2).foregroundStyle(.secondary)
                    Text("Imported").font(.caption2).foregroundStyle(.green)
                    if prop.supportsMerge { Text("Merged").font(.caption2).foregroundStyle(.blue) }
                }
                GridRow {
                    Text(model.existingValue(for: prop) ?? "—")
                        .font(.caption).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                    Text(model.importedValue(for: prop) ?? "—")
                        .font(.caption).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                    if prop.supportsMerge {
                        Text(model.mergedValue(for: prop) ?? "—")
                            .font(.caption).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            Picker("Decision for \(prop.displayName)", selection: Binding(get: { prop.decision }, set: onDecision)) {
                ForEach(prop.availableDecisions) { d in Text(d.rawValue).tag(d) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        .padding(10)
        .background(.thinMaterial)
        .clipShape(.rect(cornerRadius: 10))
    }
}

// MARK: - Three-Column NavigationSplitView

/// Sidebar (modules) → content (items) → detail (accordion). Collapses to a stack on compact width.
struct ImportReviewSplitView: View {
    @Bindable var model: ImportReviewModel
    let rootManager: RootManager?
    let onCancel: () -> Void
    let onApply: () async -> Void

    var body: some View {
        NavigationSplitView {
            List(model.modules, selection: $model.selectedModuleID) { module in
                IRModuleRow(module: module)
            }
            .navigationTitle(Text("Modules", bundle: .module))
            .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
            .onChange(of: model.selectedModuleID) { _, newID in
                guard let newID else { return }
                model.select(moduleID: newID)
            }
        } content: {
            if let module = model.selectedModule {
                IRItemContentList(module: module, selectedID: $model.selectedItemID)
                    .navigationTitle(module.name)
                    .navigationSplitViewColumnWidth(min: 240, ideal: 300, max: 380)
            } else {
                ContentUnavailableView(
                    String(localized: "Select a Module", bundle: .module),
                    systemImage: "sidebar.left"
                )
            }
        } detail: {
            if let item = model.selectedItem {
                SingleItemReviewVC_Accordion(model: item.itemModel, root: selectedModuleRoot)
                    .navigationTitle(item.name)
                    .id(item.id)
            } else {
                ContentUnavailableView(
                    String(localized: "Select an Item", bundle: .module),
                    systemImage: "doc.text"
                )
            }
        }
        .navigationSplitViewStyle(.balanced)
        .task {
            guard let rootManager else { return }
            model.resolveReferences(rootManager: rootManager)
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(role: .cancel, action: onCancel) {
                    Label { Text("Cancel", bundle: .module) } icon: { Image(systemName: "xmark") }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    Task { await onApply() }
                } label: {
                    Label { Text("Apply", bundle: .module) } icon: { Image(systemName: "checkmark.circle") }
                }
            }
        }
    }

    private var selectedModuleRoot: (any ItemRootControllable)? {
        guard let module = model.selectedModule else { return nil }
        return rootManager?.rootModel(for: module.id)
    }
}

private struct IRItemContentList: View {
    let module: ImportReviewModule
    @Binding var selectedID: ImportReviewItemModel.ID?

    private var addedItems: [ImportReviewItemModel]   { module.reviewItems.filter { $0.kind == .added } }
    private var changedItems: [ImportReviewItemModel] { module.reviewItems.filter { $0.kind == .different } }

    var body: some View {
        List(selection: $selectedID) {
            if !addedItems.isEmpty {
                Section {
                    ForEach(addedItems) { item in
                        IRItemListRow(item: item)
                    }
                } header: {
                    Text("Added", bundle: .module)
                }
            }
            if !changedItems.isEmpty {
                Section {
                    ForEach(changedItems) { item in
                        IRItemListRow(item: item)
                    }
                } header: {
                    Text("Changed", bundle: .module)
                }
            }
        }
    }
}

// MARK: - Helpers

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Preview Data

private extension ImportReviewModel {
    static var preview: ImportReviewModel {
        let previewItem = SingleItemImportModel.preview
        
        let blackKeep = ImportReviewItemModel(
            id: UUID(), kind: .different,
            existingStatus: "5 scenes, local notes kept",
            importedStatus: "7 scenes, new finale",
            mergedStatus: "7 scenes, local notes + imported finale",
            itemModel: previewItem
        )
        let frozenVault = ImportReviewItemModel(
            id: UUID(), kind: .added,
            existingStatus: "Not in library",
            importedStatus: "3 scenes, 1 map, 2 tables",
            mergedStatus: "Ready to add",
            itemModel: previewItem
        )
        let maraVenn = ImportReviewItemModel(
            id: UUID(), kind: .different,
            existingStatus: "Level 4, portrait set",
            importedStatus: "Level 5, new spell list",
            mergedStatus: "Level 5, existing portrait, combined notes",
            itemModel: previewItem
        )
        let captainHarl = ImportReviewItemModel(
            id: UUID(), kind: .added,
            existingStatus: "Not in library",
            importedStatus: "New NPC from imported adventure",
            mergedStatus: "Ready to add",
            itemModel: previewItem
        )
        
        return ImportReviewModel(modules: [
            ImportReviewModule(id: .adventure, reviewItems: [blackKeep, frozenVault]),
            ImportReviewModule(id: .value, reviewItems: [maraVenn, captainHarl]),
        ])
    }
}

// MARK: - Previews

#Preview("Split View") {
    ImportReviewSplitView(model: .preview, rootManager: nil, onCancel: {}, onApply: {})
}
