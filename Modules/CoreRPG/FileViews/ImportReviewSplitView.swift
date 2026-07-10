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
                ImportReviewSheetDetailView(
                    item: item,
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

private struct ImportReviewSheetDetailView: View {
    let item: ImportReviewItemModel
    let root: (any ItemRootControllable)?
    let rootManager: RootManager?
    let reviewModel: ImportReviewModel

    @State private var sheetRootModel: SheetRootModel?
    @State private var showsChoices = false

    var body: some View {
        if let rootManager, let rootController = root?.rootController {
            VStack(spacing: 0) {
                SingleReviewDecisionCardsView(model: item.itemModel)
                    .padding()

                Divider()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        sheetPreview(rootController: rootController)

                        DisclosureGroupTV(isExpanded: $showsChoices) {
                            SingleItemReviewChoicesView(
                                model: item.itemModel,
                                root: root,
                                rootManager: rootManager,
                                reviewModel: reviewModel
                            )
                            .padding(.top, 8)
                        } label: {
                            Label {
                                Text("Choices", bundle: .module)
                            } icon: {
                                Image(systemName: "slider.horizontal.3")
                            }
                            .font(.headline)
                        }
                        .padding()
                        .background(Color.secondary.opacity(0.05))
                        .clipShape(.rect(cornerRadius: 12))
                    }
                    .padding()
                }
            }
            .onChange(of: reviewModel.sheetMemorySignature, initial: true) { _, _ in
                rebuildSheetRootModel(rootController: rootController, rootManager: rootManager)
            }
        } else {
            SingleItemReviewAccordionView(
                model: item.itemModel,
                root: root,
                rootManager: rootManager,
                reviewModel: reviewModel
            )
        }
    }

    @ViewBuilder
    private func sheetPreview(rootController: ItemRootController) -> some View {
        if item.isDeletion && item.itemModel.decision == .imported {
            ContentUnavailableView(
                String(localized: "Will be Deleted", bundle: .module),
                systemImage: "trash"
            )
            .frame(maxWidth: .infinity)
            .padding()
        } else if let sheetRootModel {
            LazyVStack(alignment: .leading, spacing: 4) {
                SheetRootView(root: rootController, rootModel: sheetRootModel)
            }
            .animation(.default, value: item.itemModel.decisionSignature)
        } else {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding()
        }
    }

    private func rebuildSheetRootModel(rootController: ItemRootController, rootManager: RootManager) {
        let reviewRootManager = rootManager.with(reviewSheetMemory: reviewModel.sheetMemory())
        sheetRootModel = SheetRootModel(
            rootManager: reviewRootManager,
            linkControllable: rootController.linkControllable,
            sheetControllable: rootController.sheetControllable,
            itemId: item.id,
            isEditor: false
        )
    }
}
