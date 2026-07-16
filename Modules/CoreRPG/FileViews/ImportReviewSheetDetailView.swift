// @copyright André Trettin

import SwiftUI

struct ImportReviewSheetDetailView: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

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
            .animation(accessibilityReduceMotion ? nil : .default, value: item.itemModel.decisionSignature)
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

#Preview("Review Detail") {
    ImportReviewSheetDetailView(
        item: ImportReviewModel.preview.modules[0].reviewItems[0],
        root: nil,
        rootManager: nil,
        reviewModel: .preview
    )
}
