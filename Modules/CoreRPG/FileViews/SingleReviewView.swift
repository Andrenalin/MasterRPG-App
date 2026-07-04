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

                if !model.references.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("References", bundle: .module)
                            .font(.headline)
                        ForEach(model.references) { reference in
                            SingleReviewReferenceRow(reference: reference)
                        }
                    }
                }

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

                if !model.entries.isEmpty {
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
            .padding()
        }
        .navigationTitle(model.name)
    }
}
