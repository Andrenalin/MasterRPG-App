// @copyright André Trettin

import SwiftUI

struct SingleReviewEntryRow: View {
    let entry: SingleEntryImportModel
    @State private var isExpanded = false

    private var hasExisting: Bool { entry.entry.existing != nil }
    private var hasImported: Bool { entry.entry.imported != nil }

    private func summary(from source: (any EntryDataAccessable)?) -> String? {
        guard let source else { return nil }
        let namePart = entry.properties.count > 0 ? source[keyPath: entry.properties[0].valueKeyPath] : ""
        let contentPart = entry.properties.count > 1 ? source[keyPath: entry.properties[1].valueKeyPath] : ""
        let pieces = [namePart, contentPart].filter { !$0.isEmpty }
        return pieces.isEmpty ? nil : pieces.joined(separator: " — ")
    }

    private var anyPropertyChanged: Bool {
        entry.properties.contains { entry.isChanged(prop: $0) }
    }

    private var indicatorName: String {
        (!anyPropertyChanged && hasExisting && hasImported) ? "checkmark.circle.fill" : "circle.fill"
    }

    private var indicatorColor: Color {
        if !anyPropertyChanged && hasExisting && hasImported { return .secondary.opacity(0.5) }
        if hasExisting && !hasImported { return .orange }
        if hasImported && !hasExisting { return .green }
        return entry.decision.tint
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(duration: 0.3)) { isExpanded.toggle() }
            } label: {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 5) {
                        Image(systemName: indicatorName)
                            .font(.subheadline)
                            .foregroundStyle(indicatorColor)
                        SingleReviewLinkText(text: entry.name)
                            .font(.subheadline)
                            .bold()
                        Spacer()
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    if !entry.isRemovalSummary && !entry.content.isEmpty {
                        SingleReviewLinkText(text: entry.content)
                            .font(.callout)
                            .foregroundStyle(.primary)
                    }

                    if !entry.isRemovalSummary {
                        if anyPropertyChanged {
                            HStack(spacing: 4) {
                                Text("Was:", bundle: .module)
                                    .font(.caption2)
                                    .bold()
                                    .foregroundStyle(.orange)
                                SingleReviewLinkText(text: summary(from: entry.entry.existing) ?? "—")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            HStack(spacing: 4) {
                                Text("New:", bundle: .module)
                                    .font(.caption2)
                                    .bold()
                                    .foregroundStyle(.green)
                                SingleReviewLinkText(text: summary(from: entry.entry.imported) ?? "—")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        } else if hasExisting && !hasImported {
                            Text("Only in existing version", bundle: .module)
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        } else if hasImported && !hasExisting {
                            Text("Only in imported version", bundle: .module)
                                .font(.caption2)
                                .foregroundStyle(.green)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text(isExpanded ? "Collapse entry details" : "Expand entry details", bundle: .module))

            if isExpanded {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(entry.properties) { SingleReviewEntryPropertyRow(entry: entry, property: $0) }
                }
                .padding(12)
            }
        }
        .background(Color.secondary.opacity(0.05))
        .clipShape(.rect(cornerRadius: 10))
    }
}

struct SingleReviewEntryPropertyRow: View {
    let entry: SingleEntryImportModel
    let property: SingleReviewEntryProperty
    @State private var isExpanded = false

    private var isOverridden: Bool { property.decision != entry.decision }

    private var alternatives: [SingleReviewDecision] {
        property.availableDecisions.filter { $0 != property.decision }
    }

    private func value(for decision: SingleReviewDecision) -> String? {
        switch decision {
        case .existing: entry.existingValue(for: property)
        case .imported: entry.importedValue(for: property)
        case .merge: entry.mergedValue(for: property)
        }
    }

    var body: some View {
        if !entry.isChanged(prop: property) {
            HStack(spacing: 5) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(Color.secondary.opacity(0.4))
                VStack(alignment: .leading, spacing: 1) {
                    Text(property.displayName)
                        .font(.caption)
                        .bold()
                        .foregroundStyle(.secondary)
                    SingleReviewValueView(kind: property.kind, value: entry.effectiveValue(for: property), lineLimit: 1)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(8)
            .background(Color.secondary.opacity(0.03))
            .clipShape(.rect(cornerRadius: 8))
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(.spring(duration: 0.3)) { isExpanded.toggle() }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 5) {
                            Image(systemName: isOverridden ? "circle.fill" : "checkmark.circle.fill")
                                .font(.subheadline)
                                .foregroundStyle(isOverridden ? property.decision.tint : .secondary.opacity(0.5))
                            Text(property.displayName)
                                .font(.caption)
                                .bold()
                                .foregroundStyle(.secondary)
                            Spacer()
                            Label(property.decision.title, systemImage: property.decision.systemImage)
                                .font(.caption2)
                                .foregroundStyle(property.decision.tint)
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        SingleReviewValueView(kind: property.kind, value: entry.effectiveValue(for: property))
                            .font(.callout)
                            .foregroundStyle(.primary)
                            .contentTransition(.opacity)
                            .animation(.easeInOut(duration: 0.2), value: property.decision)
                        HStack(spacing: 4) {
                            Text("Was:", bundle: .module)
                                .font(.caption2)
                                .bold()
                                .foregroundStyle(.orange)
                            SingleReviewValueView(kind: property.kind, value: entry.existingValue(for: property), lineLimit: 1)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        HStack(spacing: 4) {
                            Text("New:", bundle: .module)
                                .font(.caption2)
                                .bold()
                                .foregroundStyle(.green)
                            SingleReviewValueView(kind: property.kind, value: entry.importedValue(for: property), lineLimit: 1)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(8)
                }
                .buttonStyle(.plain)
                .accessibilityHint(Text(isExpanded ? "Collapse property choices" : "Expand property choices", bundle: .module))

                if isExpanded {
                    Divider()
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(alternatives) { d in
                            SingleReviewAlternativeBlock(decision: d, kind: property.kind, value: value(for: d)) {
                                withAnimation(.spring(duration: 0.3)) {
                                    entry.setPropertyDecision(d, propertyID: property.id)
                                    isExpanded = false
                                }
                            }
                        }
                    }
                    .padding(8)
                }
            }
            .background(Color.secondary.opacity(0.05))
            .clipShape(.rect(cornerRadius: 8))
        }
    }
}
