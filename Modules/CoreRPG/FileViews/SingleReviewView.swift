// @copyright André Trettin

import SwiftUI

struct SingleItemReviewAccordionView: View {
    let model: SingleItemImportModel
    var root: (any ItemRootControllable)? = nil
    var rootManager: RootManager? = nil
    var reviewModel: ImportReviewModel? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SingleReviewDecisionCardsView(model: model)

                SingleItemReviewChoicesView(
                    model: model,
                    root: root,
                    rootManager: rootManager,
                    reviewModel: reviewModel
                )
            }
            .padding()
        }
        .navigationTitle(model.name)
    }
}

struct SingleItemReviewChoicesView: View {
    let model: SingleItemImportModel
    var root: (any ItemRootControllable)? = nil
    var rootManager: RootManager? = nil
    var reviewModel: ImportReviewModel? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if !model.references.isEmpty {
                SingleItemReviewReferencesSection(model: model)
            }

            SingleItemReviewPropertiesSection(
                model: model,
                root: root,
                rootManager: rootManager,
                reviewModel: reviewModel
            )

            if !model.entries.isEmpty {
                SingleItemReviewEntriesSection(model: model)
            }
        }
    }
}

private struct SingleItemReviewReferencesSection: View {
    let model: SingleItemImportModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("References", bundle: .module)
                .font(.headline)
            ForEach(model.references) { reference in
                SingleReviewReferenceRow(reference: reference)
            }
        }
    }
}

private struct SingleItemReviewPropertiesSection: View {
    let model: SingleItemImportModel
    var root: (any ItemRootControllable)? = nil
    var rootManager: RootManager? = nil
    var reviewModel: ImportReviewModel? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Properties", bundle: .module)
                .font(.headline)
            ForEach(model.properties) { property in
                if property.kind == .binary {
                    SingleReviewFilePropertyRow(model: model, property: property, root: root)
                } else if property.kind == .link {
                    SingleReviewLinkedPropertyRow(
                        model: model,
                        property: property,
                        rootManager: rootManager,
                        reviewModel: reviewModel
                    )
                } else {
                    SingleReviewPropertyRow(model: model, property: property)
                }
            }
        }
    }
}

private struct SingleItemReviewEntriesSection: View {
    let model: SingleItemImportModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Entries", bundle: .module)
                    .font(.headline)
                Spacer()
                if model.entriesAreIdentical {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.green)
                        .accessibilityLabel(Text("All entries exist in both versions", bundle: .module))
                } else {
                    let existingCount = model.item.existing?.entries.count ?? 0
                    let importedCount = model.item.imported?.entries.count ?? 0
                    if existingCount != importedCount {
                        Text("\(existingCount) existing · \(importedCount) imported", bundle: .module)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            ForEach(model.entries) { entry in
                SingleReviewEntryRow(entry: entry)
            }
        }
    }
}

#Preview { SingleItemReviewAccordionView(model: .preview) }
#Preview { SingleItemReviewChoicesView(model: .preview) }
#Preview { SingleItemReviewReferencesSection(model: .preview).padding() }
#Preview { SingleItemReviewPropertiesSection(model: .preview).padding() }
#Preview { SingleItemReviewEntriesSection(model: .preview).padding() }
