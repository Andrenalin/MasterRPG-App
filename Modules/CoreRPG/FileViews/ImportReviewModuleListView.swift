// @copyright André Trettin

import SwiftUI

struct ImportReviewModuleListView: View {
    @Bindable var model: ImportReviewModel

    var body: some View {
        List(model.modules, selection: $model.selectedModuleID) { module in
            ImportReviewModuleRow(module: module)
        }
        .navigationTitle(Text("Modules", bundle: .module))
        .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
        .onChange(of: model.selectedModuleID) { _, newID in
            guard let newID else { return }
            model.select(moduleID: newID)
        }
    }
}

private struct ImportReviewModuleRow: View {
    let module: ImportReviewModule

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(module.name, systemImage: module.id.icon)
                    .bold()
                Spacer()
                Text(module.reviewItems.count, format: .number)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                if !module.addedItems.isEmpty {
                    ImportReviewCountBadge(
                        count: module.addedItems.count,
                        systemImage: "circle.fill",
                        tint: .green,
                        accessibilityLabel: Text("Added items", bundle: .module)
                    )
                }

                if !module.changedItems.isEmpty {
                    ImportReviewCountBadge(
                        count: module.changedItems.count,
                        systemImage: "circle.fill",
                        tint: .orange,
                        accessibilityLabel: Text("Changed items", bundle: .module)
                    )
                }

                if module.blockedReferenceCount > 0 {
                    ImportReviewCountBadge(
                        count: module.blockedReferenceCount,
                        systemImage: "exclamationmark.triangle.fill",
                        tint: .red,
                        accessibilityLabel: Text("Blocked references", bundle: .module)
                    )
                }
            }
            .font(.caption)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            Text(
                "Module \(module.name), \(module.reviewItems.count) items, \(module.addedItems.count) added, \(module.changedItems.count) changed, \(module.blockedReferenceCount) blocked references",
                bundle: .module
            )
        )
    }
}

private struct ImportReviewCountBadge: View {
    let count: Int
    let systemImage: String
    let tint: Color
    let accessibilityLabel: Text

    var body: some View {
        Label {
            Text(count, format: .number)
        } icon: {
            Image(systemName: systemImage)
        }
        .foregroundStyle(tint)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(Text(count, format: .number))
    }
}

#Preview {
    ImportReviewCountBadge(
        count: 3,
        systemImage: "exclamationmark.triangle.fill",
        tint: .red,
        accessibilityLabel: Text("Blocked references")
    )
    .padding()
}

#Preview("Module List") {
    ImportReviewModuleListView(model: .preview)
}

#Preview("Module Row") {
    ImportReviewModuleRow(module: ImportReviewModel.preview.modules[0])
        .padding()
}
