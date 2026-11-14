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
                            thumbnail(for: property.decision)
                            VStack(alignment: .leading, spacing: 4) {
                                SingleReviewFilePropertyRowFileNamesView(wasName: wasName, newName: newName)
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

}

// MARK: - Extracted subviews (CODE_AUDIT §8.3)

private struct SingleReviewFilePropertyRowFileNamesView: View {
    let wasName: String
    let newName: String

    @ViewBuilder var body: some View {
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
    /// Byte length of one UUID, taken from the content-hash digest. See
    /// `FileUrl.versionDigestByteCount` / CODE_AUDIT.md §9.5.
    static let reviewThumbnailKeyDigestByteCount = 16

    var reviewThumbnailKey: UUID {
        guard let contentHash, let digest = Data(base64Encoded: contentHash), digest.count >= Self.reviewThumbnailKeyDigestByteCount else { return fileId }
        return DeterministicUUID.uuid(bytes: Array(digest.prefix(Self.reviewThumbnailKeyDigestByteCount)))
    }
}

#Preview("File Property") {
    let model = SingleItemImportModel.preview
    SingleReviewFilePropertyRow(model: model, property: model.properties[0], root: nil)
        .padding()
}
