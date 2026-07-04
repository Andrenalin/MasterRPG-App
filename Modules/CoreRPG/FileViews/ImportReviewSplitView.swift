// @copyright André Trettin

import SwiftUI

/// Sidebar (modules) -> content (items) -> detail (accordion). Collapses to a stack on compact width.
struct ImportReviewSplitView: View {
    @Bindable var model: ImportReviewModel
    let rootManager: RootManager?
    let onCancel: () -> Void
    let onApply: () async -> Void

    var body: some View {
        NavigationSplitView {
            ImportReviewModuleListView(model: model)
        } content: {
            if let module = model.selectedModule {
                ImportReviewItemListView(module: module, selectedID: $model.selectedItemID)
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
                SingleItemReviewAccordionView(
                    model: item.itemModel,
                    root: selectedModuleRoot,
                    rootManager: rootManager,
                    reviewModel: model
                )
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
        .task(resolveReferences)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(role: .cancel, action: onCancel) {
                    Label {
                        Text("Cancel", bundle: .module)
                    } icon: {
                        Image(systemName: "xmark")
                    }
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button(action: applyReview) {
                    Label {
                        Text("Apply", bundle: .module)
                    } icon: {
                        Image(systemName: "checkmark.circle")
                    }
                }
            }
        }
    }

    private var selectedModuleRoot: (any ItemRootControllable)? {
        guard let module = model.selectedModule else { return nil }
        return rootManager?.rootModel(for: module.id)
    }

    private func resolveReferences() async {
        guard let rootManager else { return }
        model.resolveReferences(rootManager: rootManager)
    }

    private func applyReview() {
        Task { await onApply() }
    }
}
