// @copyright André Trettin

import SwiftUI

struct SingleReviewLinkedPropertyRow: View {
    let model: SingleItemImportModel
    let property: SingleReviewItemProperty
    let rootManager: RootManager?
    let reviewModel: ImportReviewModel?
    @State private var listDisplayModel = ListDisplayModel()

    var body: some View {
        if !model.isChanged(prop: property) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(Color.secondary.opacity(0.4))
                Text(property.displayName)
                    .font(.subheadline)
                    .bold()
                Spacer()
                linkView(for: .imported, preferImported: true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.secondary.opacity(0.03))
            .clipShape(.rect(cornerRadius: 10))
            .accessibilityElement(children: .combine)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: "circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(property.decision.tint)
                    Text(property.displayName)
                        .font(.subheadline)
                        .bold()
                    Spacer()
                }
                HStack(spacing: 4) {
                    Text("Was:", bundle: .module)
                        .font(.caption2)
                        .bold()
                        .foregroundStyle(.orange)
                    linkView(for: .existing, preferImported: false)
                    Spacer()
                }
                HStack(spacing: 4) {
                    Text("New:", bundle: .module)
                        .font(.caption2)
                        .bold()
                        .foregroundStyle(.green)
                    linkView(for: .imported, preferImported: true)
                    Spacer()
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.05))
            .clipShape(.rect(cornerRadius: 10))
            .accessibilityElement(children: .combine)
        }
    }
}

private extension SingleReviewLinkedPropertyRow {
    func link(for decision: SingleReviewDecision) -> ItemRowModel? {
        guard case .link(let row) = property.reviewValue?(model.item.item(for: decision)) else { return nil }
        return row
    }

    func resolvedModel(for link: ItemRowModel, preferImported: Bool) -> (any ItemDataAccessible)? {
        reviewModel?.displayModel(for: link, preferImported: preferImported, rootManager: rootManager)
            ?? rootManager?.rootModel(for: link.typeId)?.itemControllable.itemSync(for: link.itemId)
    }

    @ViewBuilder
    func linkView(for decision: SingleReviewDecision, preferImported: Bool) -> some View {
        if let link = link(for: decision) {
            if let resolved = resolvedModel(for: link, preferImported: preferImported) {
                HStack(spacing: 8) {
                    thumbnail(for: resolved, module: link.typeId)
                    Text(resolved.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else {
                Text("Missing", bundle: .module)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } else {
            Text("Not set", bundle: .module)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    func thumbnail(for resolved: any ItemDataAccessible, module: NetworkModules) -> some View {
        if let root = rootManager?.rootModel(for: module) {
            if root.viewControllable.thumbnailRowViewType == .custom {
                root.viewControllable.thumbnailRowView(for: resolved)
            } else if root.viewControllable.thumbnailRowViewType == .photo,
                      let cacheController = root.cacheControllable {
                ThumbnailRowPhotoView(
                    cacheController: cacheController,
                    model: resolved,
                    listDisplayModel: listDisplayModel,
                    entryId: resolved.fileUrl?.reviewThumbnailKey
                )
            }
        }
    }
}

#Preview("Linked Property") {
    let model = SingleItemImportModel.preview
    SingleReviewLinkedPropertyRow(model: model, property: model.properties[0], rootManager: nil, reviewModel: nil)
        .padding()
}
