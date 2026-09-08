// @copyright André Trettin

import SwiftUI

struct SingleReviewFilePropertyRow: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    let model: SingleItemImportModel
    let property: SingleReviewItemProperty
    let root: (any ItemRootControllable)?
    @State private var isExpanded = false
    @State private var listDisplayModel = ListDisplayModel()

    private var isOverridden: Bool { property.decision != model.decision }
    private var wasName: String { model.item.item(for: .existing).fileName }
    private var newName: String { model.item.item(for: .imported).fileName }

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
                value: model.effectiveValue(for: property)
            )
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(accessibilityReduceMotion ? nil : .spring(duration: 0.3)) { isExpanded.toggle() }
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
                        HStack(alignment: .top, spacing: 10) {
                            thumbnail
                            VStack(alignment: .leading, spacing: 4) {
                                fileNames
                            }
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
                            SingleReviewFileAlternativeBlock(decision: decision, value: value(for: decision)) {
                                thumbnail(for: decision)
                            } onSelect: {
                                withAnimation(accessibilityReduceMotion ? nil : .spring(duration: 0.3)) {
                                    model.setPropertyDecision(decision, propertyId: property.id)
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

    private var thumbnail: some View {
        thumbnail(for: property.decision)
    }

    @ViewBuilder
    private func thumbnail(for decision: SingleReviewDecision) -> some View {
        let decidedItem = model.item.item(for: decision)
        if let root {
            if root.viewControllable.thumbnailRowViewType == .custom {
                root.viewControllable.thumbnailRowView(for: decidedItem)
            } else if root.viewControllable.thumbnailRowViewType == .photo,
                      let cacheController = root.cacheControllable,
                      let fileUrl = decidedItem.fileUrl {
                ThumbnailRowPhotoView(
                    cacheController: cacheController,
                    model: decidedItem,
                    listDisplayModel: listDisplayModel,
                    entryId: fileUrl.reviewThumbnailKey
                )
            }
        }
    }

    @ViewBuilder
    private var fileNames: some View {
        if wasName == newName {
            HStack(spacing: 4) {
                Text("Both:", bundle: .module)
                    .font(.caption2)
                    .bold()
                    .foregroundStyle(.secondary)
                Text(wasName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        } else {
            HStack(spacing: 4) {
                Text("Was:", bundle: .module)
                    .font(.caption2)
                    .bold()
                    .foregroundStyle(.orange)
                Text(wasName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            HStack(spacing: 4) {
                Text("New:", bundle: .module)
                    .font(.caption2)
                    .bold()
                    .foregroundStyle(.green)
                Text(newName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

extension FileUrl {
    var reviewThumbnailKey: UUID {
        guard let contentHash, let digest = Data(base64Encoded: contentHash), digest.count >= 16 else { return fileId }
        let bytes = Array(digest.prefix(16))
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}

#Preview("File Property") {
    let model = SingleItemImportModel.preview
    SingleReviewFilePropertyRow(model: model, property: model.properties[0], root: nil)
        .padding()
}
