// @copyright André Trettin
//
// Three layout variations for reviewing one imported item.
// Decision cascades: item-level sets all properties; individual overrides persist.
// Merge is the default. Binary properties (no merged version) fall back to imported on merge.

import SwiftUI

// MARK: - Model

enum SingleReviewKind {
    case text
    case tags
    case picker(options: [String])   // shown as segmented / menu picker
    case binary                       // only existing / imported, no merge version
    case sublist                      // contains nested sub-properties
    case link                         // linked item, rendered with the destination module's thumbnail
}

extension SingleReviewKind: Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.text, .text), (.binary, .binary), (.sublist, .sublist), (.link, .link): true
        case (.picker(let a), .picker(let b)):                          a == b
        default: false
        }
    }
}

enum SingleReviewDecision: String, CaseIterable, Identifiable {
    case merge    = "Merge"
    case existing = "Existing"
    case imported = "New"

    var id: Self { self }

    var systemImage: String {
        switch self {
        case .merge:    "arrow.triangle.merge"
        case .existing: "clock.arrow.circlepath"
        case .imported: "tray.and.arrow.down"
        }
    }

    var tint: Color {
        switch self {
        case .merge:    .blue
        case .existing: .orange
        case .imported: .green
        }
    }

    var tagline: String {
        switch self {
        case .merge:    String(localized: "Combine both versions", bundle: .module)
        case .existing: String(localized: "Keep your current data", bundle: .module)
        case .imported: String(localized: "Replace with imported", bundle: .module)
        }
    }
}

@MainActor
final class SingleReviewItem {
    init(existing: (any ItemDataAccessable)?, imported: (any ItemDataAccessable)?, merged: any ItemDataAccessable) {
        self.existing = existing
        self.imported = imported
        self.merged = merged
    }
    
    let existing: (any ItemDataAccessable)?
    let imported: (any ItemDataAccessable)?
    let merged: any ItemDataAccessable
    
    func item(for decision: SingleReviewDecision) -> any ItemDataAccessable {
        switch decision {
        case .existing: existing ?? merged
        case .imported: imported ?? merged
        case .merge: merged
        }
    }
}

@MainActor
final class SingleReviewEntry {
    init(existing: (any EntryDataAccessable)?, imported: (any EntryDataAccessable)?, merged: (any EntryDataAccessable)?) {
        self.existing = existing
        self.imported = imported
        self.merged = merged
    }
    
    let existing: (any EntryDataAccessable)?
    let imported: (any EntryDataAccessable)?
    let merged: (any EntryDataAccessable)?
    
    func item(for decision: SingleReviewDecision) -> (any EntryDataAccessable)? {
        switch decision {
        case .existing: existing
        case .imported: imported
        case .merge: merged
        }
    }
}

@Observable @MainActor
final class SingleReviewItemProperty: Identifiable {
    init(id: UUID, item: SingleReviewItem, displayName: String, kind: SingleReviewKind, value: @escaping @MainActor (any ItemDataAccessable) -> String, compareValue: (@MainActor (any ItemDataAccessable) -> String)? = nil, reviewValue: (@MainActor (any ItemDataAccessable) -> ReviewPropertyValue)? = nil, isReadOnly: Bool = false, decision: SingleReviewDecision, apply: @escaping @MainActor (inout any ItemDataAccessable, any ItemDataAccessable) -> Void) {
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
    /// Reads the displayed string representation from one model version.
    let value: @MainActor (any ItemDataAccessable) -> String
    /// Used to detect changes; defaults to `value`. The File property compares the
    /// stable content identity instead of the displayed name, so the same binary stored
    /// at a different location does not show up as a change.
    let compareValue: @MainActor (any ItemDataAccessable) -> String
    /// The typed value of a custom model property, e.g. `.link` for photoId / diceId.
    let reviewValue: (@MainActor (any ItemDataAccessable) -> ReviewPropertyValue)?
    /// Display only, no per-property decision — the value follows the item decision.
    let isReadOnly: Bool
    /// Writes this property from the decided source model into the final model.
    let apply: @MainActor (inout any ItemDataAccessable, any ItemDataAccessable) -> Void

    var decision: SingleReviewDecision

    var supportsMerge: Bool { kind != .binary }

    var availableDecisions: [SingleReviewDecision] {
        supportsMerge ? SingleReviewDecision.allCases : [.existing, .imported]
    }
}

@Observable @MainActor
final class SingleReviewEntryProperty: Identifiable {
    init(id: UUID, entry: SingleReviewEntry, displayName: String, kind: SingleReviewKind, valueKeyPath: KeyPath<any EntryDataAccessable, String>, decision: SingleReviewDecision, apply: @escaping (inout any EntryDataAccessable, any EntryDataAccessable) -> Void) {
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
    let valueKeyPath: KeyPath<any EntryDataAccessable, String>
    /// Writes this property from the decided source entry into the final entry.
    let apply: (inout any EntryDataAccessable, any EntryDataAccessable) -> Void

    var decision: SingleReviewDecision

    var supportsMerge: Bool { kind != .binary }

    var availableDecisions: [SingleReviewDecision] {
        supportsMerge ? SingleReviewDecision.allCases : [.existing, .imported]
    }
}

@Observable @MainActor
final class SingleReviewReference: Identifiable {
    enum Status {
        case resolved      // item already exists in the app
        case pendingImport // item is being imported in this batch
        case missing       // item is not available
    }

    init(itemName: String, destination: ItemRowModel, existsInLibrary: Bool, pendingItem: ImportReviewItemModel? = nil) {
        self.itemName = itemName
        self.destination = destination
        self.existsInLibrary = existsInLibrary
        self.pendingItem = pendingItem
        self.fixedStatus = nil
    }

    /// Preview/testing initializer with a fixed status.
    init(itemName: String, destination: ItemRowModel, status: Status) {
        self.itemName = itemName
        self.destination = destination
        self.existsInLibrary = status == .resolved
        self.pendingItem = nil
        self.fixedStatus = status
    }

    let id = UUID()
    let itemName: String
    /// The link target: itemId, entryId and module of the referenced item.
    let destination: ItemRowModel
    /// Whether the destination already exists in the local database.
    let existsInLibrary: Bool
    /// The review item that creates (or deletes) the destination when applied.
    weak var pendingItem: ImportReviewItemModel?
    private let fixedStatus: Status?

    var module: NetworkModules { destination.typeId }
    var moduleName: String { destination.typeId.title }

    /// Recomputed whenever the decision of the destination review item changes.
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
    init(item: SingleReviewItem, properties: [SingleReviewItemProperty], entries: [SingleEntryImportModel], references: [SingleReviewReference], decision: SingleReviewDecision = .merge) {
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
    
    func setPropertyDecision(_ newDecision: SingleReviewDecision, propertyID: UUID) {
        seek(in: properties, id: propertyID, to: newDecision)
        entries.forEach {
            $0.setPropertyDecision(newDecision, propertyID: propertyID)
        }
    }
    
    var hasPropertyOverrides: Bool {
        properties.contains { defaultDecision(for: $0) != $0.decision }
    }

    var entriesAreIdentical: Bool {
        entries.allSatisfy { $0.entry.existing != nil && $0.entry.imported != nil }
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
        properties.first(where: { $0.id == id })?.decision = newDecision
    }
    
    var name: String {
        guard let firstProperty = properties.first else { return "No name found" }
        return firstProperty.value(item.item(for: firstProperty.decision))
    }

    var description: String {
        guard properties.count > 1 else { return "No description found" }
        let firstProperty = properties[1]
        return firstProperty.value(item.item(for: firstProperty.decision))
    }
    
    func hasOverride(for property: SingleReviewItemProperty) -> Bool {
        let hasDecision = properties.first(where: { $0.id == property.id })?.decision ?? .merge
        return hasDecision != decision
    }
}


@Observable @MainActor
final class SingleEntryImportModel: Identifiable {
    init(entry: SingleReviewEntry, properties: [SingleReviewEntryProperty], references: [SingleReviewReference], decision: SingleReviewDecision = .merge) {
        self.id = entry.existing?.id ?? UUID()
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
    
    func setPropertyDecision(_ newDecision: SingleReviewDecision, propertyID: UUID) {
        seek(in: properties, id: propertyID, to: newDecision)
    }
    
    var hasPropertyOverrides: Bool {
        properties.contains { defaultDecision(for: $0) != $0.decision }
    }
    
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
        properties.first(where: { $0.id == id })?.decision = newDecision
    }
    
    var name: String {
        guard let firstProperty = properties.first, let item = entry.item(for: firstProperty.decision) else { return "No name found" }
        return item[keyPath: firstProperty.valueKeyPath]
    }
    
    var content: String {
        guard properties.count > 1 else { return "No content found" }
        let firstProperty = properties[1]
        let item = entry.item(for: firstProperty.decision)
        return item?[keyPath: firstProperty.valueKeyPath] ?? "No content found"
    }
    
}
// MARK: - Preview Data

extension SingleItemImportModel {
    // MARK: - Real Item Mapping

    // Maps three pre-computed ItemDataAccessable snapshots into a review item.
    // The UI never computes a merge; existing/imported/merged are provided by the caller
    // (typically the CRDT merge layer). Pass existing == imported and merged == imported
    // when there is no prior version.
    @MainActor static func from(item: SingleReviewItem) -> SingleItemImportModel {
        var props: [SingleReviewItemProperty] = []

        props.append(SingleReviewItemProperty(id: UUID(), item: item, displayName: "Name", kind: .text, value: { $0.name }, decision: .merge) { $0.name = $1.name })
        props.append(SingleReviewItemProperty(id: UUID(), item: item, displayName: "Description", kind: .text, value: { $0.description }, decision: .merge) { $0.description = $1.description })
        props.append(SingleReviewItemProperty(id: UUID(), item: item, displayName: "Tags", kind: .tags, value: { $0.tagLine }, decision: .merge) { $0.tags = $1.tags })
        // File row only for models that carry a file — modules without file support always have a nil fileUrl
        if item.existing?.fileUrl != nil || item.imported?.fileUrl != nil || item.merged.fileUrl != nil {
            props.append(SingleReviewItemProperty(id: UUID(), item: item, displayName: "File", kind: .binary, value: { $0.fileName }, compareValue: { $0.fileIdentity }, decision: .imported) { $0.fileUrl = $1.fileUrl })
        }

        // Custom model properties (toggles, enums, numbers) rendered via their string
        // representation — read only, the value follows the item decision on apply.
        // Link values (photoId / diceId) render with the destination module's thumbnail.
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
        
        // entries — sub-properties paired by name; id = "entry-<entryName>"
        let existingEntries = item.existing?.entries ?? []
        let importedEntries = item.imported?.entries ?? []
        let mergedEntries   = item.merged.entries
        let entries = (existingEntries + importedEntries + mergedEntries)
            .map(\.id)
            .reduce(into: [UUID]()) { if !$0.contains($1) { $0.append($1) } }
            .map { SingleItemImportModel.from(item: item, entryId: $0)}
        
        // References are resolved once all items are imported, see ImportReviewModel.resolveReferences(rootManager:)
        return SingleItemImportModel(item: item, properties: props, entries: entries, references: [])
    }
    
    static func from(
        item: SingleReviewItem,
        entryId: UUID
    ) -> SingleEntryImportModel {
        let exiting = item.existing?.entries.first(where: { $0.id == entryId })
        let imported = item.imported?.entries.first(where: { $0.id == entryId })
        let merged = item.merged.entries.first(where: { $0.id == entryId })
        let entry = SingleReviewEntry(existing: exiting, imported: imported, merged: merged)
        var props: [SingleReviewEntryProperty] = []
        

        props.append(SingleReviewEntryProperty(id: UUID(), entry: entry, displayName: "Name", kind: .text, valueKeyPath: \.name, decision: .merge) { $0.name = $1.name })
        props.append(SingleReviewEntryProperty(id: UUID(), entry: entry, displayName: "Content", kind: .text, valueKeyPath: \.content, decision: .merge) { $0.content = $1.content })
        return SingleEntryImportModel(entry: entry, properties: props, references: [])
    }
}

// MARK: - Materialize Decisions

extension SingleItemImportModel {
    /// Whether any property or entry deviates from the item-level decision.
    var hasOverrides: Bool {
        hasPropertyOverrides || entries.contains { $0.decision != decision || $0.hasPropertyOverrides }
    }

    /// Builds the final model with the item, property and entry decisions applied.
    func materializedItem() -> any ItemDataAccessable {
        var result = item.item(for: decision).copy()
        for property in properties {
            property.apply(&result, item.item(for: property.decision))
        }
        result.replaceEntries(with: entries.compactMap { $0.materializedEntry() })
        return result
    }
}

extension SingleEntryImportModel {
    /// The final entry for the current decisions; nil drops the entry from the item.
    func materializedEntry() -> (any EntryDataAccessable)? {
        guard var result = entry.item(for: decision) else { return nil }
        for property in properties {
            guard let source = entry.item(for: property.decision) else { continue }
            property.apply(&result, source)
        }
        return result
    }
}

private extension ItemDataAccessable {
    @MainActor func replaceEntries(with newEntries: [any EntryDataAccessable]) {
        entries = newEntries.compactMap { $0 as? Entry }
    }
}

// MARK: - Display Value Helpers

extension SingleItemImportModel {
    func existingValue(for prop: SingleReviewItemProperty) -> String? { value(from: item.item(for: .existing), for: prop) }
    func importedValue(for prop: SingleReviewItemProperty) -> String? { value(from: item.item(for: .imported), for: prop) }
    func mergedValue  (for prop: SingleReviewItemProperty) -> String? { value(from: item.item(for: .merge),   for: prop) }

    func effectiveValue(for prop: SingleReviewItemProperty) -> String? {
        value(from: item.item(for: prop.decision), for: prop)
    }

    func isChanged(prop: SingleReviewItemProperty) -> Bool {
        prop.compareValue(item.item(for: .existing)) != prop.compareValue(item.item(for: .imported))
    }

    private func value(from item: any ItemDataAccessable, for prop: SingleReviewItemProperty) -> String? {
        prop.value(item).nilIfEmpty
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

extension SingleEntryImportModel {
    func existingValue(for prop: SingleReviewEntryProperty) -> String? {
        let v = entry.existing?[keyPath: prop.valueKeyPath] ?? ""; return v.isEmpty ? nil : v
    }
    func importedValue(for prop: SingleReviewEntryProperty) -> String? {
        let v = entry.imported?[keyPath: prop.valueKeyPath] ?? ""; return v.isEmpty ? nil : v
    }
    func mergedValue(for prop: SingleReviewEntryProperty) -> String? {
        let v = entry.merged?[keyPath: prop.valueKeyPath] ?? ""; return v.isEmpty ? nil : v
    }
    func effectiveValue(for prop: SingleReviewEntryProperty) -> String? {
        let v = entry.item(for: prop.decision)?[keyPath: prop.valueKeyPath] ?? ""; return v.isEmpty ? nil : v
    }
    func isChanged(prop: SingleReviewEntryProperty) -> Bool {
        existingValue(for: prop) != importedValue(for: prop)
    }
}

// MARK: - Preview Data

// MARK: - Preview Models

// A minimal ItemDataAccessable conformance for SwiftUI previews only.
// Uses EmtpyEntryViewModel (public) as Entry to avoid needing FakeItemModel (internal).
@Observable
private final class PreviewItemModel: @unchecked Sendable {
    typealias Entry = EmtpyEntryViewModel

    var id: UUID
    var name: String
    var category: ItemListCategory
    var description: String
    var tags: [String]
    var displayState: Int
    var isGroupHiddenToggle: Bool
    var entries: [EmtpyEntryViewModel]
    var fileUrl: FileUrl?
    var parentId: UUID?

    var isGroupHidden: Bool { isGroupHiddenToggle }

    init(id: UUID = UUID(), name: String, category: ItemListCategory = .photo,
         description: String = "", tags: [String] = [],
         fileUrl: FileUrl? = nil, entries: [EmtpyEntryViewModel] = []) {
        self.id = id; self.name = name; self.category = category
        self.description = description; self.tags = tags
        self.displayState = 0; self.isGroupHiddenToggle = false
        self.entries = entries; self.fileUrl = fileUrl; self.parentId = nil
    }

    subscript(entryId: UUID) -> EmtpyEntryViewModel {
        get { entries.first { $0.id == entryId } ?? .empty }
        set { entries = entries.map { $0.id == entryId ? newValue : $0 } }
    }

    static var empty: PreviewItemModel { PreviewItemModel(name: "") }
    static func empty(_ id: UUID) -> PreviewItemModel { PreviewItemModel(id: id, name: "") }
    static var typeId: NetworkModules { .none }

    func copy()      -> PreviewItemModel { PreviewItemModel(id: id, name: name, category: category, description: description, tags: tags, fileUrl: fileUrl, entries: entries) }
    func duplicate() -> PreviewItemModel { copy() }
    func filter(filter: String, includeEntries: Bool) -> Bool { true }
    func isEqual(other: PreviewItemModel) -> Bool { id == other.id }
    @MainActor func replace(with model: PreviewItemModel) -> Bool { false }
    static func == (lhs: PreviewItemModel, rhs: PreviewItemModel) -> Bool { lhs.id == rhs.id }
}

extension SingleItemImportModel {
    // Preview using .from() so the factory and view helpers are exercised.
    static var preview: SingleItemImportModel {
        var bg = EmtpyEntryViewModel.empty;  bg.name = "Background"; bg.content = "Born in Frosthold, trained as a border scout."
        var notes = EmtpyEntryViewModel.empty; notes.name = "Notes"; notes.content = "Knows the old password for the Black Keep."
        var bg2 = EmtpyEntryViewModel.empty; bg2.name = "Background"; bg2.content = "Born in Frosthold, now serving aboard The Dread."
        var ability = EmtpyEntryViewModel.empty; ability.name = "Abilities"; ability.content = "Mist step, shadow blend."

        let existingItem = PreviewItemModel(
            name: "Mara Venn", category: .photo, description: "A suspicious ranger.",
            tags: ["npc", "ranger", "suspicious"], entries: [bg, notes]
        )
        let importedItem = PreviewItemModel(
            name: "Mara Venn", category: .photo, description: "A loyal rogue who serves Captain Harl.",
            tags: ["loyal", "npc", "rogue"],
            fileUrl: FileUrl(fileId: UUID(), url: URL(filePath: "/portraits/mara.png"), location: .appCloud, module: "photo", relativeUrl: nil),
            entries: [bg2, ability]
        )
        var mergedBg = EmtpyEntryViewModel.empty; mergedBg.name = "Background"; mergedBg.content = "Born in Frosthold, now serving aboard The Dread."
        let mergedItem = PreviewItemModel(
            name: "Mara Venn", category: .photo,
            description: "A loyal rogue who serves Captain Harl.",
            tags: ["loyal", "npc", "ranger", "rogue", "suspicious"],
            fileUrl: importedItem.fileUrl,
            entries: [mergedBg, notes, ability]
        )
        let item = SingleReviewItem(existing: existingItem, imported: importedItem, merged: mergedItem)
        let model = SingleItemImportModel.from(item: item)
        model.references = [SingleReviewReference(itemName: "Black Keep", destination: ItemRowModel(itemId: UUID(), typeId: .adventure), status: .missing)]
        return model
    }
}

extension ItemDataAccessable {
    @MainActor var fileName: String {
        guard let fileUrl else { return "No file set" }
        let name = fileUrl.rawUrl.lastPathComponent
        return name.isEmpty ? fileUrl.rawValue : name
    }

    /// Stable identity for change detection: the content hash when available, so the same
    /// binary at a different location compares equal and changed data at the same url does
    /// not. Falls back to the raw url representation for legacy items without a hash.
    @MainActor var fileIdentity: String {
        guard let fileUrl else { return "" }
        return fileUrl.contentHash ?? fileUrl.rawValue
    }

    @MainActor var tagLine: String {
        tags.joined(separator: ",")
    }
}

// MARK: - Shared Components

struct SRItemHeader: View {
    let item: SingleItemImportModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.name).font(.title2).bold()
            Text(item.description).foregroundStyle(.secondary)
        }
    }
}

struct ReviewDecisionCards: View {
    let model: SingleItemImportModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SRItemHeader(item: model)

            HStack(spacing: 10) {
                ForEach(SingleReviewDecision.allCases) { d in
                    Button {
                        model.applyItemDecision(d)
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: d.systemImage).font(.title2)
                            Text(d.rawValue).font(.subheadline).bold()
                            Text(d.tagline).font(.caption2).multilineTextAlignment(.center)
                                .foregroundStyle(model.decision == d ? d.tint : .secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(model.decision == d ? d.tint.opacity(0.14) : Color.secondary.opacity(0.06))
                        .foregroundStyle(model.decision == d ? d.tint : .secondary)
                        .clipShape(.rect(cornerRadius: 14))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(model.decision == d ? d.tint : Color.clear, lineWidth: 2)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            if model.hasPropertyOverrides {
                Label("Some properties have custom overrides", systemImage: "slider.horizontal.3")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}


private struct SRDecisionBar: View {
    let decision: SingleReviewDecision
    let hasOverrides: Bool
    let onChange: (SingleReviewDecision) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ForEach(SingleReviewDecision.allCases) { d in
                    SRDecisionPill(d: d, isSelected: decision == d) { onChange(d) }
                }
            }
            if hasOverrides {
                Label("Some properties have custom overrides", systemImage: "slider.horizontal.3")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }
}

private struct SRDecisionPill: View {
    let d: SingleReviewDecision
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(d.rawValue, systemImage: d.systemImage)
                .font(.subheadline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(isSelected ? d.tint.opacity(0.16) : Color.secondary.opacity(0.08))
                .foregroundStyle(isSelected ? d.tint : .secondary)
                .clipShape(.rect(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(isSelected ? d.tint : Color.clear, lineWidth: 1.5)
                }
        }
        .buttonStyle(.plain)
    }
}

// Binary property: only existing / imported, no merge option.
private struct SRBinaryToggle: View {
    let model: SingleItemImportModel
    let property: SingleReviewItemProperty

    var body: some View {
        HStack(spacing: 0) {
            SRBinarySide(
                label: "Existing", value: model.effectiveValue(for: property),
                isSelected: property.decision == .existing, tint: .orange
            ) {
                property.decision = .existing
            }
            Divider().frame(height: 44)
            SRBinarySide(
                label: "New", value: model.importedValue(for: property),
                isSelected: property.decision == .imported, tint: .green
            ) { property.decision = .imported }
        }
        .clipShape(.rect(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8).strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
        }
    }
}

private struct SRBinarySide: View {
    let label: String
    let value: String?
    let isSelected: Bool
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Text(label).font(.caption2).bold()
                Text(value ?? "—").font(.caption).lineLimit(2)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 10)
            .background(isSelected ? tint.opacity(0.16) : Color.secondary.opacity(0.06))
            .foregroundStyle(isSelected ? tint : .secondary)
        }
        .buttonStyle(.plain)
    }
}

private struct SRReferenceRow: View {
    let reference: SingleReviewReference

    var body: some View {
        HStack {
            Image(systemName: reference.status.systemImage).foregroundStyle(reference.status.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(reference.itemName)
                Text(reference.moduleName).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            reference.status.label.font(.caption2).foregroundStyle(reference.status.tint)
        }
        .padding(10)
        .background(reference.status.tint.opacity(0.08))
        .clipShape(.rect(cornerRadius: 8))
    }
}

// MARK: - Reference Status UI Helpers

extension SingleReviewReference.Status {
    var systemImage: String {
        switch self {
        case .resolved:      "checkmark.circle.fill"
        case .pendingImport: "arrow.down.circle.fill"
        case .missing:       "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .resolved:      .green
        case .pendingImport: .orange
        case .missing:       .red
        }
    }

    var label: Text {
        switch self {
        case .resolved:      Text("Resolved", bundle: .module)
        case .pendingImport: Text("Pending Import", bundle: .module)
        case .missing:       Text("Missing", bundle: .module)
        }
    }
}

// MARK: - Additional Preview Data

extension SingleItemImportModel {
    // New item, no local version exists; existing == imported == merged, no conflicts.
    static var previewNewImport: SingleItemImportModel {
        var lore = EmtpyEntryViewModel.empty
        lore.name = "Lore"
        lore.content = "The Crimson Codex is an ancient tome sealed with three locks, each requiring a different key held by a different faction. Its pages shift language depending on who reads them, and every third moon it whispers the name of someone who will soon die."

        var spells = EmtpyEntryViewModel.empty
        spells.name = "Spell List"
        spells.content = "Fireball (3rd), Chain Lightning (6th), Meteor Swarm (9th), Time Stop (9th), Wish (9th). Requires attunement by a wizard of 15th level or higher."

        let snapshot = PreviewItemModel(
            name: "Crimson Codex",
            category: .photo,
            description: "A legendary artifact of immense power, sought by wizards across three continents. Its pages are said to contain forbidden knowledge of the primordial age — spells erased from all other records after the Sundering.",
            tags: ["artifact", "legendary", "magic", "tome", "attunement"],
            entries: [lore, spells]
        )
        let reviewItem = SingleReviewItem(existing: snapshot, imported: snapshot, merged: snapshot)
        let model = SingleItemImportModel.from(item: reviewItem)
        model.references = [
            SingleReviewReference(itemName: "The Vault of Eternity", destination: ItemRowModel(itemId: UUID(), typeId: .adventure), status: .resolved),
            SingleReviewReference(itemName: "Elara the Archivist", destination: ItemRowModel(itemId: UUID(), typeId: .value), status: .missing)
        ]
        return model
    }

    // Existing and imported have completely different entries; merged picks from both.
    // Each entry is existing-only, imported-only, or merged-from-both depending on which
    // versions share a UUID — entries with distinct UUIDs appear as separate sources.
    static var previewConflictingEntries: SingleItemImportModel {
        var existingHistory = EmtpyEntryViewModel.empty
        existingHistory.name = "History"
        existingHistory.content = "Founded in the third age by refugees from the Sunken Isles, Thornwall grew from a fishing village into a trade fortress. Its eastern gate has never been breached in four centuries of recorded conflict."

        var existingNPCs = EmtpyEntryViewModel.empty
        existingNPCs.name = "Key NPCs"
        existingNPCs.content = "Mayor Brynn Holt — pragmatic, bribeable. Captain Sera — loyal to the crown above all else. The Fence known only as Dusty — last seen near the harbour, whereabouts now unknown."

        var existingSecrets = EmtpyEntryViewModel.empty
        existingSecrets.name = "Secrets"
        existingSecrets.content = "A hidden passage beneath the granary connects to the old smugglers' dock. Only the mayor and Dusty know its exact location. The passage floods at high tide."

        // Shared entry: same UUID in both versions, different content — exercises Was/New + per-property selection
        var existingOverview = EmtpyEntryViewModel.empty
        existingOverview.name = "Overview"
        existingOverview.content = "Thornwall stands at the junction of the Ashen coast and the inland trade road, a modest but strategically vital settlement that has remained neutral for four generations."
        var importedOverview = existingOverview   // copies UUID
        importedOverview.content = "Thornwall is a chokepoint. Whoever controls its amber flow controls the northern economy. The Guild knows this. So does the Crown."

        var existingFactions = EmtpyEntryViewModel.empty
        existingFactions.name = "Factions"
        existingFactions.content = "Amber Merchants' Guild (dominant), Fisher's Brotherhood (declining since the new dock taxes), The Watch (formally neutral, unofficially bought by the Guild over the past two years)."

        var existingEconomy = EmtpyEntryViewModel.empty
        existingEconomy.name = "Economy"
        existingEconomy.content = "Primary exports: amber, salted fish, timber. The amber trade accounts for nearly 60% of all town revenue. A blocked sea lane could destabilise the entire settlement within weeks."

        var importedRumors = EmtpyEntryViewModel.empty
        importedRumors.name = "Rumors"
        importedRumors.content = "Locals whisper that the mayor sold passage rights to a Thieves' Guild convoy last season. The harbour tax records were allegedly altered to conceal three shipments of untaxed amber."

        var importedEvents = EmtpyEntryViewModel.empty
        importedEvents.name = "Recent Events"
        importedEvents.content = "A fire destroyed the western warehouse district three weeks ago. No cause was officially determined. Six bodies recovered; two remain unidentified. Guild marks were found on the salvage."

        var importedTradeRoutes = EmtpyEntryViewModel.empty
        importedTradeRoutes.name = "Trade Routes"
        importedTradeRoutes.content = "Three overland routes connect Thornwall to the interior. The southern road through Mirewood is fastest but now subject to Guild tolls. The coastal path is longer but avoids all checkpoints."

        var importedMilitary = EmtpyEntryViewModel.empty
        importedMilitary.name = "Military Presence"
        importedMilitary.content = "Twelve Watch soldiers nominally under the mayor's command. Six mercenaries recently hired by the Merchants' Guild. No naval force — the harbour is entirely undefended from the sea."

        var importedDangers = EmtpyEntryViewModel.empty
        importedDangers.name = "Dangers"
        importedDangers.content = "Thieves' Guild expansion. Potential arson if the mayor fails to cooperate. Unknown buyer for stolen amber manifests. At least one Guild informant is embedded inside The Watch."

        let existingItem = PreviewItemModel(
            name: "Thornwall",
            category: .photo,
            description: "A fortified coastal trade town on the edge of the Ashen Reach. Known for amber trade and political neutrality — though neither may last much longer given the Guild pressure building from the south.",
            tags: ["location", "town", "coastal", "trade"],
            entries: [existingOverview, existingHistory, existingNPCs, existingSecrets, existingFactions, existingEconomy]
        )
        let importedItem = PreviewItemModel(
            name: "Thornwall",
            category: .photo,
            description: "Trade hub on the Ashen Reach. Recent unrest and suspicious fires suggest the mayor's neutrality has been compromised. Thieves' Guild operatives are moving in from the south road.",
            tags: ["conflict", "guild", "location", "town"],
            entries: [importedOverview, importedRumors, importedEvents, importedTradeRoutes, importedMilitary, importedDangers]
        )
        let mergedItem = PreviewItemModel(
            name: "Thornwall",
            category: .photo,
            description: "A fortified coastal trade town on the edge of the Ashen Reach. Known for amber trade and political neutrality — though neither may last much longer given the Guild pressure building from the south.",
            tags: ["coastal", "conflict", "guild", "location", "town", "trade"],
            entries: [importedOverview, existingHistory, existingNPCs, existingSecrets, existingFactions, existingEconomy,
                      importedRumors, importedEvents, importedTradeRoutes, importedMilitary, importedDangers]
        )
        let reviewItem = SingleReviewItem(existing: existingItem, imported: importedItem, merged: mergedItem)
        let model = SingleItemImportModel.from(item: reviewItem)
        model.references = [
            SingleReviewReference(itemName: "Ashen Reach Region", destination: ItemRowModel(itemId: UUID(), typeId: .map), status: .resolved),
            SingleReviewReference(itemName: "The Mayor's Ledger", destination: ItemRowModel(itemId: UUID(), typeId: .adventure), status: .pendingImport),
            SingleReviewReference(itemName: "Brynn Holt", destination: ItemRowModel(itemId: UUID(), typeId: .value), status: .resolved)
        ]
        return model
    }
}

// MARK: - VC: Accordion Form

// Static row — no conflict: all three values identical, no interaction.
private struct VC_StaticPropertyRow: View {
    let displayName: String
    let value: String?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.caption2).foregroundStyle(Color.secondary.opacity(0.4))
            VStack(alignment: .leading, spacing: 2) {
                Text(displayName).font(.subheadline).bold()
                Text(value ?? "—").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Color.secondary.opacity(0.03))
        .clipShape(.rect(cornerRadius: 10))
    }
}

// Linked item property (photoId / diceId) — read only, renders the destination module's
// thumbnail plus the linked item's name for the existing and imported version. The linked
// model is resolved from the import batch first because imported items are not in the
// database yet, then from the database.
private struct VC_LinkPropertyRow: View {
    let model: SingleItemImportModel
    let property: SingleReviewItemProperty
    let rootManager: RootManager?
    let reviewModel: ImportReviewModel?
    @State private var listDisplayModel = ListDisplayModel()

    var body: some View {
        if !model.isChanged(prop: property) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption2).foregroundStyle(Color.secondary.opacity(0.4))
                Text(property.displayName).font(.subheadline).bold()
                Spacer()
                linkView(for: .imported, preferImported: true)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Color.secondary.opacity(0.03))
            .clipShape(.rect(cornerRadius: 10))
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: "circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(property.decision.tint)
                    Text(property.displayName).font(.subheadline).bold()
                    Spacer()
                }
                HStack(spacing: 4) {
                    Text("Was:").font(.caption2).bold().foregroundStyle(.orange)
                    linkView(for: .existing, preferImported: false)
                    Spacer()
                }
                HStack(spacing: 4) {
                    Text("New:").font(.caption2).bold().foregroundStyle(.green)
                    linkView(for: .imported, preferImported: true)
                    Spacer()
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.05))
            .clipShape(.rect(cornerRadius: 10))
        }
    }
}

private extension VC_LinkPropertyRow {
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
                    Text(resolved.name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            } else {
                Text("Missing", bundle: .module).font(.caption).foregroundStyle(.red)
            }
        } else {
            Text("Not set", bundle: .module).font(.caption).foregroundStyle(.secondary)
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

// Read-only custom property that changed — shows the effective value (follows the item
// decision) with Was/New lines, but offers no per-property choice.
private struct VC_ReadOnlyPropertyRow: View {
    let model: SingleItemImportModel
    let property: SingleReviewItemProperty

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: "circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(property.decision.tint)
                Text(property.displayName).font(.subheadline).bold()
                Spacer()
            }
            Text(model.effectiveValue(for: property) ?? "—")
                .font(.callout)
                .foregroundStyle(.primary)
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: property.decision)
            HStack(spacing: 4) {
                Text("Was:").font(.caption2).bold().foregroundStyle(.orange)
                Text(model.existingValue(for: property) ?? "—")
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            HStack(spacing: 4) {
                Text("New:").font(.caption2).bold().foregroundStyle(.green)
                Text(model.importedValue(for: property) ?? "—")
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.05))
        .clipShape(.rect(cornerRadius: 10))
    }
}

// Conflict row — indicator inline with name, full effective value below, Was/New each on own line.
// Expand shows the two non-selected alternatives; selecting one animates the value and closes.
private struct VC_AccordionRow: View {
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
        case .merge:    model.mergedValue(for: property)
        }
    }

    var body: some View {
        if !model.isChanged(prop: property) {
            VC_StaticPropertyRow(displayName: property.displayName,
                                 value: model.effectiveValue(for: property))
        } else if property.isReadOnly {
            VC_ReadOnlyPropertyRow(model: model, property: property)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(.spring(duration: 0.3)) { isExpanded.toggle() }
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        // Indicator + name + chevron — all inline, no content indentation
                        HStack(spacing: 5) {
                            Image(systemName: isOverridden ? "circle.fill" : "checkmark.circle.fill")
                                .font(.subheadline)
                                .foregroundStyle(isOverridden ? property.decision.tint : .secondary.opacity(0.5))
                            Text(property.displayName).font(.subheadline).bold()
                            Spacer()
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption).foregroundStyle(.tertiary)
                        }
                        // Effective value — cross-fades when decision changes
                        Text(model.effectiveValue(for: property) ?? "—")
                            .font(.callout)
                            .foregroundStyle(.primary)
                            .contentTransition(.opacity)
                            .animation(.easeInOut(duration: 0.2), value: property.decision)
                        // Was / New — each on its own line
                        HStack(spacing: 4) {
                            Text("Was:").font(.caption2).bold().foregroundStyle(.orange)
                            Text(model.existingValue(for: property) ?? "—")
                                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                        HStack(spacing: 4) {
                            Text("New:").font(.caption2).bold().foregroundStyle(.green)
                            Text(model.importedValue(for: property) ?? "—")
                                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 12)
                }
                .buttonStyle(.plain)

                if isExpanded {
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(alternatives) { d in
                            VC_AlternativeBlock(decision: d, value: value(for: d)) {
                                withAnimation(.spring(duration: 0.3)) {
                                    model.setPropertyDecision(d, propertyID: property.id)
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
}

private struct VC_AlternativeBlock: View {
    let decision: SingleReviewDecision
    let value: String?
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 5) {
                Label(decision.rawValue, systemImage: decision.systemImage)
                    .font(.caption2).bold().foregroundStyle(decision.tint)
                Text(value ?? "—")
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(.primary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(decision.tint.opacity(0.08))
            .clipShape(.rect(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(decision.tint.opacity(0.2), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

struct SingleItemReviewVC_Accordion: View {
    let model: SingleItemImportModel
    var root: (any ItemRootControllable)? = nil
    var rootManager: RootManager? = nil
    var reviewModel: ImportReviewModel? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ReviewDecisionCards(model: model)

                if !model.references.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("References").font(.headline)
                        ForEach(model.references) { SRReferenceRow(reference: $0) }
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Properties").font(.headline)
                    ForEach(model.properties) { prop in
                        if prop.kind == .binary {
                            VC_FileAccordionRow(model: model, property: prop, root: root)
                        } else if prop.kind == .link {
                            VC_LinkPropertyRow(model: model, property: prop, rootManager: rootManager, reviewModel: reviewModel)
                        } else {
                            VC_AccordionRow(model: model, property: prop)
                        }
                    }
                }

                if !model.entries.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Entries").font(.headline)
                            Spacer()
                            if model.entriesAreIdentical {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.subheadline).foregroundStyle(.green)
                            } else {
                                let ex = model.item.existing?.entries.count ?? 0
                                let im = model.item.imported?.entries.count ?? 0
                                if ex != im {
                                    Text("\(ex) existing · \(im) imported")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        ForEach(model.entries) { VC_EntryAccordion(entry: $0) }
                    }
                }
            }
            .padding()
        }
        .navigationTitle(model.name)
    }
}

// File property row — the raw filename text is not helpful, so when the file changed
// this shows a thumbnail preview (photo or module custom view, see ViewControllable)
// next to the filenames. Identical filenames collapse into a single "Both:" line.
private struct VC_FileAccordionRow: View {
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
        case .merge:    model.mergedValue(for: property)
        }
    }

    var body: some View {
        if !model.isChanged(prop: property) {
            VC_StaticPropertyRow(displayName: property.displayName,
                                 value: model.effectiveValue(for: property))
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
                            Text(property.displayName).font(.subheadline).bold()
                            Spacer()
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption).foregroundStyle(.tertiary)
                        }
                        HStack(alignment: .top, spacing: 10) {
                            thumbnail
                            VStack(alignment: .leading, spacing: 4) {
                                fileNames
                            }
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 12)
                }
                .buttonStyle(.plain)

                if isExpanded {
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(alternatives) { d in
                            VC_FileAlternativeBlock(decision: d, value: value(for: d)) {
                                thumbnail(for: d)
                            } onSelect: {
                                withAnimation(.spring(duration: 0.3)) {
                                    model.setPropertyDecision(d, propertyID: property.id)
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
                // Keyed per binary so the existing and imported previews get their own
                // cache slots and do not overwrite the item's list thumbnail.
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
                Text("Both:").font(.caption2).bold().foregroundStyle(.secondary)
                Text(wasName).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        } else {
            HStack(spacing: 4) {
                Text("Was:").font(.caption2).bold().foregroundStyle(.orange)
                Text(wasName).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            HStack(spacing: 4) {
                Text("New:").font(.caption2).bold().foregroundStyle(.green)
                Text(newName).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}

private extension FileUrl {
    /// Stable cache key that is distinct per binary — existing and imported can share
    /// the same fileId, but their content hashes differ exactly when the files differ.
    var reviewThumbnailKey: UUID {
        guard let contentHash, let digest = Data(base64Encoded: contentHash), digest.count >= 16 else { return fileId }
        let bytes = Array(digest.prefix(16))
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}

// Decision alternative for the file property — shows the thumbnail of that version
// next to the filename so the user sees what each choice looks like.
private struct VC_FileAlternativeBlock<Thumbnail: View>: View {
    let decision: SingleReviewDecision
    let value: String?
    @ViewBuilder let thumbnail: () -> Thumbnail
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 10) {
                thumbnail()
                VStack(alignment: .leading, spacing: 5) {
                    Label(decision.rawValue, systemImage: decision.systemImage)
                        .font(.caption2).bold().foregroundStyle(decision.tint)
                    Text(value ?? "—")
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(.primary)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(decision.tint.opacity(0.08))
            .clipShape(.rect(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(decision.tint.opacity(0.2), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

// Review text can contain RPG:// markdown links; render them read-only, no toggling.
private struct VC_LinkText: View {
    init(text: String) {
        self.text = text
        _model = State(initialValue: LinkHighlightTextModel(linkControllable: nil, text: text))
    }

    let text: String
    @State private var model: LinkHighlightTextModel

    var body: some View {
        LinkHighlightTextView(model: model)
            .onChange(of: text) { _, newText in
                model.reset(text: newText)
            }
    }
}

private struct VC_EntryAccordion: View {
    let entry: SingleEntryImportModel
    @State private var isExpanded = false

    private var hasExisting: Bool { entry.entry.existing != nil }
    private var hasImported: Bool { entry.entry.imported != nil }

    // "Name — Content" single-line summary for Was/New
    private func summary(from source: (any EntryDataAccessable)?) -> String? {
        guard let source else { return nil }
        let namePart  = entry.properties.count > 0 ? source[keyPath: entry.properties[0].valueKeyPath] : ""
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
                            .font(.subheadline).foregroundStyle(indicatorColor)
                        VC_LinkText(text: entry.name).font(.subheadline).bold()
                        Spacer()
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                    VC_LinkText(text: entry.content)
                        .font(.callout).foregroundStyle(.primary)
                    if anyPropertyChanged {
                        HStack(spacing: 4) {
                            Text("Was:").font(.caption2).bold().foregroundStyle(.orange)
                            Text(summary(from: entry.entry.existing) ?? "—")
                                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                        HStack(spacing: 4) {
                            Text("New:").font(.caption2).bold().foregroundStyle(.green)
                            Text(summary(from: entry.entry.imported) ?? "—")
                                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                    } else if hasExisting && !hasImported {
                        Text("Only in existing version").font(.caption2).foregroundStyle(.orange)
                    } else if hasImported && !hasExisting {
                        Text("Only in imported version").font(.caption2).foregroundStyle(.green)
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(entry.properties) { VC_EntryPropertyAccordion(entry: entry, property: $0) }
                }
                .padding(12)
            }
        }
        .background(Color.secondary.opacity(0.05))
        .clipShape(.rect(cornerRadius: 10))
    }
}

// Interactive accordion for a single entry property — mirrors VC_AccordionRow.
// Each sub-property (Name, Content) gets its own independent decision.
private struct VC_EntryPropertyAccordion: View {
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
        case .merge:    entry.mergedValue(for: property)
        }
    }

    var body: some View {
        if !entry.isChanged(prop: property) {
            HStack(spacing: 5) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.subheadline).foregroundStyle(Color.secondary.opacity(0.4))
                VStack(alignment: .leading, spacing: 1) {
                    Text(property.displayName).font(.caption).bold().foregroundStyle(.secondary)
                    Text(entry.effectiveValue(for: property) ?? "—")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
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
                            Text(property.displayName).font(.caption).bold().foregroundStyle(.secondary)
                            Spacer()
                            Label(property.decision.rawValue, systemImage: property.decision.systemImage)
                                .font(.caption2).foregroundStyle(property.decision.tint)
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                        Text(entry.effectiveValue(for: property) ?? "—")
                            .font(.callout).foregroundStyle(.primary)
                            .contentTransition(.opacity)
                            .animation(.easeInOut(duration: 0.2), value: property.decision)
                        HStack(spacing: 4) {
                            Text("Was:").font(.caption2).bold().foregroundStyle(.orange)
                            Text(entry.existingValue(for: property) ?? "—")
                                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                        HStack(spacing: 4) {
                            Text("New:").font(.caption2).bold().foregroundStyle(.green)
                            Text(entry.importedValue(for: property) ?? "—")
                                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .padding(8)
                }
                .buttonStyle(.plain)

                if isExpanded {
                    Divider()
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(alternatives) { d in
                            VC_AlternativeBlock(decision: d, value: value(for: d)) {
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

#Preview("VC · Accordion") {
    NavigationStack { SingleItemReviewVC_Accordion(model: .previewConflictingEntries) }
}


// Conformance in an extension so witness inference does not isolate the members.
extension PreviewItemModel: ItemDataAccessable {}
