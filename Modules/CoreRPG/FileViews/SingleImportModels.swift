// @copyright André Trettin

import SwiftUI

// Split out of SingleReviewModels.swift — see CODE_AUDIT_19 §9.23.

@Observable @MainActor
final class SingleItemImportModel {
    init(
        item: SingleReviewItem,
        properties: [SingleReviewItemProperty],
        entries: [SingleEntryImportModel],
        references: [SingleReviewReference],
        decision: SingleReviewDecision = .merge
    ) {
        self.item = item
        self.properties = properties
        self.entries = entries
        self.references = references
        self.decision = decision
    }

    let item: SingleReviewItem
    let properties: [SingleReviewItemProperty]
    let entries: [SingleEntryImportModel]
    var references: [SingleReviewReference]

    var decision: SingleReviewDecision = .merge

    func applyItemDecision(_ newDecision: SingleReviewDecision) {
        decision = newDecision
        for property in properties {
            cascade(property, parent: newDecision)
        }
        for entry in entries {
            entry.applyItemDecision(newDecision)
        }
    }

    func setPropertyDecision(_ newDecision: SingleReviewDecision, propertyId: UUID) {
        seek(in: properties, id: propertyId, to: newDecision)
        entries.forEach {
            $0.setPropertyDecision(newDecision, propertyId: propertyId)
        }
    }

    var hasPropertyOverrides: Bool {
        properties.contains { defaultDecision(for: $0) != $0.decision }
    }

    var entriesAreIdentical: Bool {
        entries.allSatisfy { $0.entry.existing != nil && $0.entry.imported != nil }
    }

    var name: String {
        guard let firstProperty = properties.first else {
            return String(localized: "No name found", bundle: .module)
        }
        return firstProperty.value(item.item(for: firstProperty.decision))
    }

    var description: String {
        guard properties.count > 1 else {
            return String(localized: "No description found", bundle: .module)
        }
        let firstProperty = properties[1]
        return firstProperty.value(item.item(for: firstProperty.decision))
    }

    private func cascade(_ prop: SingleReviewItemProperty, parent: SingleReviewDecision) {
        prop.decision = defaultDecision(for: prop, given: parent)
    }

    private func defaultDecision(for prop: SingleReviewItemProperty, given parent: SingleReviewDecision? = nil) -> SingleReviewDecision {
        switch parent ?? decision {
        case .merge: prop.supportsMerge ? .merge : .imported
        case .existing: .existing
        case .imported: .imported
        }
    }

    private func seek(in props: [SingleReviewItemProperty], id: UUID, to newDecision: SingleReviewDecision) {
        props.first(where: { $0.id == id })?.decision = newDecision
    }
}

@Observable @MainActor
final class SingleEntryImportModel: Identifiable {
    init(
        entry: SingleReviewEntry,
        properties: [SingleReviewEntryProperty],
        references: [SingleReviewReference],
        decision: SingleReviewDecision = .merge
    ) {
        self.id = entry.existing?.id ?? entry.imported?.id ?? entry.merged?.id ?? UUID()
        self.entry = entry
        self.properties = properties
        self.references = references
        self.decision = decision
    }

    let id: UUID
    let entry: SingleReviewEntry
    let properties: [SingleReviewEntryProperty]
    var references: [SingleReviewReference]

    var decision: SingleReviewDecision = .merge

    func applyItemDecision(_ newDecision: SingleReviewDecision) {
        decision = newDecision
        for property in properties {
            cascade(property, parent: newDecision)
        }
    }

    func setPropertyDecision(_ newDecision: SingleReviewDecision, propertyId: UUID) {
        seek(in: properties, id: propertyId, to: newDecision)
    }

    var hasPropertyOverrides: Bool {
        properties.contains { defaultDecision(for: $0) != $0.decision }
    }

    var hasDifferences: Bool {
        entry.hasDifferences
    }

    var isRemovalSummary: Bool {
        guard let firstProperty = properties.first else { return false }
        return entry.item(for: firstProperty.decision) == nil
    }

    var name: String {
        guard let firstProperty = properties.first else {
            return String(localized: "No name found", bundle: .module)
        }
        guard let item = entry.item(for: firstProperty.decision) else { return Self.removalSummaryText }
        return item[keyPath: firstProperty.valueKeyPath]
    }

    var content: String {
        guard properties.count > 1 else {
            return String(localized: "No content found", bundle: .module)
        }
        let firstProperty = properties[1]
        guard let item = entry.item(for: firstProperty.decision) else { return "" }
        return item[keyPath: firstProperty.valueKeyPath]
    }

    private static let removalSummaryText = String(localized: "Will be removed", bundle: .module)

    private func cascade(_ prop: SingleReviewEntryProperty, parent: SingleReviewDecision) {
        prop.decision = defaultDecision(for: prop, given: parent)
    }

    private func defaultDecision(for prop: SingleReviewEntryProperty, given parent: SingleReviewDecision? = nil) -> SingleReviewDecision {
        switch parent ?? decision {
        case .merge: prop.supportsMerge ? .merge : .imported
        case .existing: .existing
        case .imported: .imported
        }
    }

    private func seek(in props: [SingleReviewEntryProperty], id: UUID, to newDecision: SingleReviewDecision) {
        props.first(where: { $0.id == id })?.decision = newDecision
    }
}

extension SingleItemImportModel {
    @MainActor static func from(item: SingleReviewItem) -> SingleItemImportModel {
        var props: [SingleReviewItemProperty] = []

        props.append(SingleReviewItemProperty(
            id: UUID(),
            item: item,
            displayName: String(localized: "Name", bundle: .module),
            kind: .text,
            value: { $0.name },
            decision: .merge
        ) { $0.name = $1.name })
        props.append(SingleReviewItemProperty(
            id: UUID(),
            item: item,
            displayName: String(localized: "Description", bundle: .module),
            kind: .text,
            value: { $0.description },
            decision: .merge
        ) { $0.description = $1.description })
        props.append(SingleReviewItemProperty(
            id: UUID(),
            item: item,
            displayName: String(localized: "Tags", bundle: .module),
            kind: .tags,
            value: { $0.tagLine },
            decision: .merge
        ) { $0.tags = $1.tags })

        if item.existing?.fileUrl != nil || item.imported?.fileUrl != nil || item.merged.fileUrl != nil {
            props.append(SingleReviewItemProperty(
                id: UUID(),
                item: item,
                displayName: String(localized: "File", bundle: .module),
                kind: .binary,
                value: { $0.fileName },
                compareValue: { $0.fileIdentity },
                decision: .imported
            ) { $0.fileUrl = $1.fileUrl })
        }

        for custom in (item.imported ?? item.merged).reviewProperties {
            let isLink = if case .link = custom.value(item.merged) { true } else { false }
            props.append(SingleReviewItemProperty(
                id: UUID(),
                item: item,
                displayName: custom.displayName,
                kind: isLink ? .link : .text,
                value: { custom.value($0).displayText },
                reviewValue: custom.value,
                isReadOnly: true,
                decision: .merge,
                apply: { _, _ in }
            ))
        }

        let existingEntries = item.existing?.entries ?? []
        let importedEntries = item.imported?.entries ?? []
        let mergedEntries = item.merged.entries
        // Indexed by id once. Collecting the ids with `Array.contains` and then three
        // `first(where:)` per entry was quadratic, and hex cells are entries: a map with a few
        // thousand of them cost tens of millions of comparisons per item.
        // See CODE_AUDIT_21 §7.2.
        func firstById(_ entries: [any EntryDataAccessible]) -> [UUID: any EntryDataAccessible] {
            Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        }
        let existingById = firstById(existingEntries)
        let importedById = firstById(importedEntries)
        let mergedById = firstById(mergedEntries)
        var seenIds: Set<UUID> = []
        let entries = (existingEntries + importedEntries + mergedEntries)
            .map(\.id)
            .filter { seenIds.insert($0).inserted }
            .map { id in
                SingleItemImportModel.from(entry: SingleReviewEntry(
                    existing: existingById[id],
                    imported: importedById[id],
                    merged: mergedById[id]
                ))
            }

        return SingleItemImportModel(item: item, properties: props, entries: entries, references: [])
    }

    static func from(item: SingleReviewItem, entryId: UUID) -> SingleEntryImportModel {
        from(entry: SingleReviewEntry(
            existing: item.existing?.entries.first(where: { $0.id == entryId }),
            imported: item.imported?.entries.first(where: { $0.id == entryId }),
            merged: item.merged.entries.first(where: { $0.id == entryId })
        ))
    }

    static func from(entry: SingleReviewEntry) -> SingleEntryImportModel {
        let props = [
            SingleReviewEntryProperty(
                id: UUID(),
                entry: entry,
                displayName: String(localized: "Name", bundle: .module),
                kind: .text,
                valueKeyPath: \.name,
                decision: .merge
            ) { $0.name = $1.name },
            SingleReviewEntryProperty(
                id: UUID(),
                entry: entry,
                displayName: String(localized: "Content", bundle: .module),
                kind: .text,
                valueKeyPath: \.content,
                decision: .merge
            ) { $0.content = $1.content }
        ]

        return SingleEntryImportModel(entry: entry, properties: props, references: [])
    }
}

extension SingleItemImportModel {
    var hasOverrides: Bool {
        hasPropertyOverrides || entries.contains { $0.decision != decision || $0.hasPropertyOverrides }
    }

    var decisionSignature: String {
        let propertySignature = properties.map { "\($0.id.uuidString):\($0.decision.rawValue)" }.joined(separator: "|")
        let entrySignature = entries.map(\.decisionSignature).joined(separator: "|")
        return "\(decision.rawValue)|\(propertySignature)|\(entrySignature)"
    }

    /// The decisions `decisionSignature` describes, without building its strings.
    func combineDecisions(into hasher: inout Hasher) {
        hasher.combine(decision)
        for property in properties {
            hasher.combine(property.id)
            hasher.combine(property.decision)
        }
        for entry in entries {
            hasher.combine(entry.id)
            hasher.combine(entry.decision)
            for property in entry.properties {
                hasher.combine(property.id)
                hasher.combine(property.decision)
            }
        }
    }

    func materializedItem() -> any ItemDataAccessible {
        var result = item.item(for: decision).copy()
        for property in properties {
            property.apply(&result, item.item(for: property.decision))
        }
        result.replaceEntries(with: entries.compactMap { $0.materializedEntry() })
        return result
    }

    /// Creates a whole-item snapshot for review without changing any live decisions.
    func materializedItem(for decision: SingleReviewDecision) -> any ItemDataAccessible {
        var result = item.item(for: decision).copy()
        for property in properties {
            let propertyDecision = defaultDecision(for: property, given: decision)
            property.apply(&result, item.item(for: propertyDecision))
        }
        result.replaceEntries(with: entries.compactMap { $0.materializedEntry(for: decision) })
        return result
    }
}

extension SingleEntryImportModel {
    var decisionSignature: String {
        let propertySignature = properties.map { "\($0.id.uuidString):\($0.decision.rawValue)" }.joined(separator: "|")
        return "\(id.uuidString):\(decision.rawValue)|\(propertySignature)"
    }

    func materializedEntry() -> (any EntryDataAccessible)? {
        guard var result = entry.item(for: decision) else { return nil }
        for property in properties {
            guard let source = entry.item(for: property.decision) else { continue }
            property.apply(&result, source)
        }
        return result
    }

    /// Creates a whole-entry snapshot for review without changing any live decisions.
    func materializedEntry(for decision: SingleReviewDecision) -> (any EntryDataAccessible)? {
        guard var result = entry.item(for: decision) else { return nil }
        for property in properties {
            let propertyDecision = defaultDecision(for: property, given: decision)
            guard let source = entry.item(for: propertyDecision) else { continue }
            property.apply(&result, source)
        }
        return result
    }
}

private extension ItemDataAccessible {
    @MainActor func replaceEntries(with newEntries: [any EntryDataAccessible]) {
        entries = newEntries.compactMap { $0 as? Entry }
    }
}

extension SingleItemImportModel {
    func existingValue(for prop: SingleReviewItemProperty) -> String? {
        value(from: item.item(for: .existing), for: prop)
    }

    func importedValue(for prop: SingleReviewItemProperty) -> String? {
        value(from: item.item(for: .imported), for: prop)
    }

    func mergedValue(for prop: SingleReviewItemProperty) -> String? {
        value(from: item.item(for: .merge), for: prop)
    }

    func effectiveValue(for prop: SingleReviewItemProperty) -> String? {
        value(from: item.item(for: prop.decision), for: prop)
    }

    func isChanged(prop: SingleReviewItemProperty) -> Bool {
        prop.compareValue(item.item(for: .existing)) != prop.compareValue(item.item(for: .imported))
    }

    private func value(from item: any ItemDataAccessible, for prop: SingleReviewItemProperty) -> String? {
        prop.value(item).nilIfEmpty
    }
}

extension SingleEntryImportModel {
    func existingValue(for prop: SingleReviewEntryProperty) -> String? {
        entry.existing?[keyPath: prop.valueKeyPath].nilIfEmpty
    }

    func importedValue(for prop: SingleReviewEntryProperty) -> String? {
        entry.imported?[keyPath: prop.valueKeyPath].nilIfEmpty
    }

    func mergedValue(for prop: SingleReviewEntryProperty) -> String? {
        entry.merged?[keyPath: prop.valueKeyPath].nilIfEmpty
    }

    func effectiveValue(for prop: SingleReviewEntryProperty) -> String? {
        entry.item(for: prop.decision)?[keyPath: prop.valueKeyPath].nilIfEmpty
    }

    func isChanged(prop: SingleReviewEntryProperty) -> Bool {
        existingValue(for: prop) != importedValue(for: prop)
    }
}

extension ItemDataAccessible {
    @MainActor var fileName: String {
        guard let fileUrl else { return String(localized: "No file set", bundle: .module) }
        let name = fileUrl.rawUrl.lastPathComponent
        return name.isEmpty ? fileUrl.rawValue : name
    }

    @MainActor var fileIdentity: String {
        guard let fileUrl else { return "" }
        return fileUrl.contentHash ?? fileUrl.rawValue
    }

    @MainActor var tagLine: String {
        tags.joined(separator: ",")
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
