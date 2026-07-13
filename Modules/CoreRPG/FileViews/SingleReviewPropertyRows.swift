// @copyright André Trettin

import SwiftUI

struct SingleReviewStaticPropertyRow: View {
    let displayName: String
    var kind: SingleReviewKind = .text
    let value: String?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(Color.secondary.opacity(0.4))
            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.subheadline)
                    .bold()
                SingleReviewValueView(kind: kind, value: value, lineLimit: 1)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.secondary.opacity(0.03))
        .clipShape(.rect(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }
}

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

    func resolvedModel(for link: ItemRowModel, preferImported: Bool) -> (any ItemDataAccessable)? {
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
    func thumbnail(for resolved: any ItemDataAccessable, module: NetworkModules) -> some View {
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

struct SingleReviewReadOnlyPropertyRow: View {
    let model: SingleItemImportModel
    let property: SingleReviewItemProperty

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: "circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(property.decision.tint)
                Text(property.displayName)
                    .font(.subheadline)
                    .bold()
                Spacer()
            }
            SingleReviewValueView(kind: property.kind, value: model.effectiveValue(for: property))
                .font(.callout)
                .foregroundStyle(.primary)
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: property.decision)
            HStack(spacing: 4) {
                Text("Was:", bundle: .module)
                    .font(.caption2)
                    .bold()
                    .foregroundStyle(.orange)
                SingleReviewValueView(kind: property.kind, value: model.existingValue(for: property), lineLimit: 1)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 4) {
                Text("New:", bundle: .module)
                    .font(.caption2)
                    .bold()
                    .foregroundStyle(.green)
                SingleReviewValueView(kind: property.kind, value: model.importedValue(for: property), lineLimit: 1)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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

#Preview {
    SingleReviewStaticPropertyRow(displayName: "Description", value: "A suspicious ranger.")
        .padding()
}

#Preview {
    let model = SingleItemImportModel.preview
    SingleReviewReadOnlyPropertyRow(model: model, property: model.properties[0])
        .padding()
}

struct SingleReviewPropertyRow: View {
    let model: SingleItemImportModel
    let property: SingleReviewItemProperty
    @State private var isExpanded = false

    private var isOverridden: Bool { property.decision != model.decision }

    private var alternatives: [SingleReviewDecision] {
        property.availableDecisions.filter { $0 != property.decision }
    }

    private func value(for decision: SingleReviewDecision) -> String? {
        switch decision {
        case .existing: model.existingValue(for: property)
        case .imported: model.importedValue(for: property)
        case .merge: model.mergedValue(for: property)
        }
    }

    var body: some View {
        if !model.isChanged(prop: property) {
            SingleReviewStaticPropertyRow(
                displayName: property.displayName,
                kind: property.kind,
                value: model.effectiveValue(for: property)
            )
        } else if property.isReadOnly {
            SingleReviewReadOnlyPropertyRow(model: model, property: property)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(.spring(duration: 0.3)) { isExpanded.toggle() }
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 5) {
                            Image(systemName: isOverridden ? "circle.fill" : "checkmark.circle.fill")
                                .font(.subheadline)
                                .foregroundStyle(isOverridden ? property.decision.tint : .secondary.opacity(0.5))
                            Text(property.displayName)
                                .font(.subheadline)
                                .bold()
                            Spacer()
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        SingleReviewValueView(kind: property.kind, value: model.effectiveValue(for: property))
                            .font(.callout)
                            .foregroundStyle(.primary)
                            .contentTransition(.opacity)
                            .animation(.easeInOut(duration: 0.2), value: property.decision)
                        HStack(spacing: 4) {
                            Text("Was:", bundle: .module)
                                .font(.caption2)
                                .bold()
                                .foregroundStyle(.orange)
                            SingleReviewValueView(kind: property.kind, value: model.existingValue(for: property), lineLimit: 1)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        HStack(spacing: 4) {
                            Text("New:", bundle: .module)
                                .font(.caption2)
                                .bold()
                                .foregroundStyle(.green)
                            SingleReviewValueView(kind: property.kind, value: model.importedValue(for: property), lineLimit: 1)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                .accessibilityHint(expansionHint)

                if isExpanded {
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(alternatives) { decision in
                            SingleReviewAlternativeBlock(decision: decision, kind: property.kind, value: value(for: decision)) {
                                withAnimation(.spring(duration: 0.3)) {
                                    model.setPropertyDecision(decision, propertyID: property.id)
                                    isExpanded = false
                                }
                            }
                        }
                    }
                    .padding(12)
                }
            }
            .background(Color.secondary.opacity(0.05))
            .clipShape(.rect(cornerRadius: 10))
        }
    }

    private var expansionHint: Text {
        isExpanded ? Text("Collapse choices", bundle: .module) : Text("Show choices", bundle: .module)
    }
}

#Preview("Property") {
    let model = SingleItemImportModel.preview
    SingleReviewPropertyRow(model: model, property: model.properties[0])
        .padding()
}

#Preview("Linked Property") {
    let model = SingleItemImportModel.preview
    SingleReviewLinkedPropertyRow(model: model, property: model.properties[0], rootManager: nil, reviewModel: nil)
        .padding()
}
