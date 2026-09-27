// @copyright André Trettin

import SwiftUI

enum SingleReviewKind {
    case text
    case tags
    case picker(options: [String])
    case binary
    case sublist
    case link
}

extension SingleReviewKind: Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.text, .text), (.binary, .binary), (.sublist, .sublist), (.link, .link): true
        case (.picker(let a), .picker(let b)): a == b
        default: false
        }
    }
}

enum SingleReviewDecision: String, CaseIterable, Identifiable {
    case merge = "Merge"
    case existing = "Existing"
    case imported = "New"

    var id: Self { self }

    var title: String {
        switch self {
        case .merge: String(localized: "Merge", bundle: .module)
        case .existing: String(localized: "Existing", bundle: .module)
        case .imported: String(localized: "New", bundle: .module)
        }
    }

    var systemImage: String {
        switch self {
        case .merge: "arrow.triangle.merge"
        case .existing: "clock.arrow.circlepath"
        case .imported: "tray.and.arrow.down"
        }
    }

    var tint: Color {
        switch self {
        case .merge: .blue
        case .existing: .orange
        case .imported: .green
        }
    }

    var tagline: String {
        switch self {
        case .merge: String(localized: "Combine both versions", bundle: .module)
        case .existing: String(localized: "Keep your current data", bundle: .module)
        case .imported: String(localized: "Replace with imported", bundle: .module)
        }
    }
}

@MainActor
final class SingleReviewItem {
    init(existing: (any ItemDataAccessible)?, imported: (any ItemDataAccessible)?, merged: any ItemDataAccessible) {
        self.existing = existing
        self.imported = imported
        self.merged = merged
    }

    let existing: (any ItemDataAccessible)?
    let imported: (any ItemDataAccessible)?
    let merged: any ItemDataAccessible

    func item(for decision: SingleReviewDecision) -> any ItemDataAccessible {
        switch decision {
        case .existing: existing ?? merged
        case .imported: imported ?? merged
        case .merge: merged
        }
    }
}

@MainActor
final class SingleReviewEntry {
    init(existing: (any EntryDataAccessible)?, imported: (any EntryDataAccessible)?, merged: (any EntryDataAccessible)?) {
        self.existing = existing
        self.imported = imported
        self.merged = merged
    }

    let existing: (any EntryDataAccessible)?
    let imported: (any EntryDataAccessible)?
    let merged: (any EntryDataAccessible)?

    func item(for decision: SingleReviewDecision) -> (any EntryDataAccessible)? {
        switch decision {
        case .existing: existing
        case .imported: imported
        case .merge: merged
        }
    }

    var hasDifferences: Bool {
        switch (existing, imported) {
        case (nil, nil):
            false
        case (.some, nil), (nil, .some):
            true
        case let (.some(existing), .some(imported)):
            !entriesAreSemanticallySame(existing, imported)
        }
    }
}

@MainActor
private func entriesAreSemanticallySame(
    _ existing: any EntryDataAccessible,
    _ imported: any EntryDataAccessible
) -> Bool {
    if let comparable = existing as? any ItemDiffComparable,
       let isSame = compareEntry(comparable, with: imported) {
        return isSame
    }

    return compareBasicEntry(existing, with: imported) ?? false
}

@MainActor
private func compareEntry<Entry: ItemDiffComparable>(
    _ existing: Entry,
    with imported: any EntryDataAccessible
) -> Bool? {
    guard let imported = imported as? Entry else { return nil }
    return existing.isSame(imported)
}

private func compareBasicEntry<Entry: EntryDataAccessible>(
    _ existing: Entry,
    with imported: any EntryDataAccessible
) -> Bool? {
    guard let imported = imported as? Entry else { return nil }
    return existing.name == imported.name && existing.content == imported.content
}

@Observable @MainActor
final class SingleReviewItemProperty: Identifiable {
    init(
        id: UUID,
        item: SingleReviewItem,
        displayName: String,
        kind: SingleReviewKind,
        value: @escaping @MainActor (any ItemDataAccessible) -> String,
        compareValue: (@MainActor (any ItemDataAccessible) -> String)? = nil,
        reviewValue: (@MainActor (any ItemDataAccessible) -> ReviewPropertyValue)? = nil,
        isReadOnly: Bool = false,
        decision: SingleReviewDecision,
        apply: @escaping @MainActor (inout any ItemDataAccessible, any ItemDataAccessible) -> Void
    ) {
        self.id = id
        self.item = item
        self.displayName = displayName
        self.kind = kind
        self.value = value
        self.compareValue = compareValue ?? value
        self.reviewValue = reviewValue
        self.isReadOnly = isReadOnly
        self.decision = decision
        self.apply = apply
    }

    let id: UUID
    let item: SingleReviewItem
    let displayName: String
    let kind: SingleReviewKind
    let value: @MainActor (any ItemDataAccessible) -> String
    let compareValue: @MainActor (any ItemDataAccessible) -> String
    let reviewValue: (@MainActor (any ItemDataAccessible) -> ReviewPropertyValue)?
    let isReadOnly: Bool
    let apply: @MainActor (inout any ItemDataAccessible, any ItemDataAccessible) -> Void

    var decision: SingleReviewDecision

    var supportsMerge: Bool { kind != .binary }

    var availableDecisions: [SingleReviewDecision] {
        supportsMerge ? SingleReviewDecision.allCases : [.existing, .imported]
    }
}

@Observable @MainActor
final class SingleReviewEntryProperty: Identifiable {
    init(
        id: UUID,
        entry: SingleReviewEntry,
        displayName: String,
        kind: SingleReviewKind,
        valueKeyPath: KeyPath<any EntryDataAccessible, String>,
        decision: SingleReviewDecision,
        apply: @escaping (inout any EntryDataAccessible, any EntryDataAccessible) -> Void
    ) {
        self.id = id
        self.entry = entry
        self.displayName = displayName
        self.kind = kind
        self.valueKeyPath = valueKeyPath
        self.decision = decision
        self.apply = apply
    }

    let id: UUID
    let entry: SingleReviewEntry
    let displayName: String
    let kind: SingleReviewKind
    let valueKeyPath: KeyPath<any EntryDataAccessible, String>
    let apply: (inout any EntryDataAccessible, any EntryDataAccessible) -> Void

    var decision: SingleReviewDecision

    var supportsMerge: Bool { kind != .binary }

    var availableDecisions: [SingleReviewDecision] {
        supportsMerge ? SingleReviewDecision.allCases : [.existing, .imported]
    }
}

@Observable @MainActor
final class SingleReviewReference: Identifiable {
    enum Status {
        case resolved
        case pendingImport
        case missing
    }

    init(itemName: String, destination: ItemRowModel, existsInLibrary: Bool, pendingItem: ImportReviewItemModel? = nil) {
        self.itemName = itemName
        self.destination = destination
        self.existsInLibrary = existsInLibrary
        self.pendingItem = pendingItem
        self.fixedStatus = nil
    }

    init(itemName: String, destination: ItemRowModel, status: Status) {
        self.itemName = itemName
        self.destination = destination
        self.existsInLibrary = status == .resolved
        self.pendingItem = nil
        self.fixedStatus = status
    }

    let id = UUID()
    let itemName: String
    let destination: ItemRowModel
    let existsInLibrary: Bool
    weak var pendingItem: ImportReviewItemModel?
    private let fixedStatus: Status?

    var module: NetworkModules { destination.typeId }
    var moduleName: String { destination.typeId.title }

    var status: Status {
        if let fixedStatus { return fixedStatus }
        if let pendingItem {
            if pendingItem.isDeletion {
                return pendingItem.itemModel.decision == .imported ? .missing : (existsInLibrary ? .resolved : .missing)
            }
            if pendingItem.itemModel.decision != .existing { return .pendingImport }
        }
        return existsInLibrary ? .resolved : .missing
    }

    var isResolved: Bool { status == .resolved }
}

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
        let entries = (existingEntries + importedEntries + mergedEntries)
            .map(\.id)
            .reduce(into: [UUID]()) { if !$0.contains($1) { $0.append($1) } }
            .map { SingleItemImportModel.from(item: item, entryId: $0) }

        return SingleItemImportModel(item: item, properties: props, entries: entries, references: [])
    }

    static func from(item: SingleReviewItem, entryId: UUID) -> SingleEntryImportModel {
        let existing = item.existing?.entries.first(where: { $0.id == entryId })
        let imported = item.imported?.entries.first(where: { $0.id == entryId })
        let merged = item.merged.entries.first(where: { $0.id == entryId })
        let entry = SingleReviewEntry(existing: existing, imported: imported, merged: merged)
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
