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
                Image(systemName: ref.isResolved ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(ref.isResolved ? .green : .red)
                VStack(alignment: .leading, spacing: 1) {
                    Text(ref.itemName)
                    Text(ref.moduleName).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(ref.isResolved ? "OK" : "Missing")
                    .font(.caption2)
                    .foregroundStyle(ref.isResolved ? .green : .red)
            }
            .padding(10)
            .background(ref.isResolved ? Color.green.opacity(0.08) : Color.red.opacity(0.1))
            .clipShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityHint(ref.isResolved ? "Reference is resolved" : "Navigate to select this referenced item")
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

// MARK: - V1: Three-Column NavigationSplitView

/// Classic sidebar → item list → detail panel. Best for iPad and Mac.
struct ImportReviewV1SplitView: View {
    @Bindable var model: ImportReviewModel

    var body: some View {
        NavigationSplitView {
            List(selection: $model.selectedModuleID) {
                ForEach(model.modules) { module in
                    IRModuleRow(module: module).tag(module.id)
                }
            }
            .navigationTitle("Modules")
        } content: {
            if let module = model.selectedModule {
                V1ItemList(module: module, selectedID: $model.selectedItemID)
                    .navigationTitle(module.name)
            } else {
                ContentUnavailableView("Select a module", systemImage: "sidebar.left")
            }
        } detail: {
            if let item = model.selectedItem {
                SingleItemReviewVC_Accordion(model: item.itemModel)
                    .navigationTitle(item.name)
                    .id(item.id)
            } else {
                ContentUnavailableView("Select an item to review", systemImage: "list.bullet.rectangle")
            }
        }
    }
}

private struct V1ItemList: View {
    let module: ImportReviewModule
    @Binding var selectedID: ImportReviewItemModel.ID?

    private var addedItems: [ImportReviewItemModel]   { module.reviewItems.filter { $0.kind == .added } }
    private var changedItems: [ImportReviewItemModel] { module.reviewItems.filter { $0.kind == .different } }

    var body: some View {
        List(selection: $selectedID) {
            if !addedItems.isEmpty {
                Section("Added") {
                    ForEach(addedItems) { item in IRItemListRow(item: item).tag(item.id) }
                }
            }
            if !changedItems.isEmpty {
                Section("Changed") {
                    ForEach(changedItems) { item in IRItemListRow(item: item).tag(item.id) }
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

#Preview("V1 · Split View") {
    ImportReviewV1SplitView(model: .preview)
}
