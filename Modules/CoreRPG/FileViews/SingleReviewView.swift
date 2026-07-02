// @copyright André Trettin
//
// Three layout variations for reviewing one imported item.
// Decision cascades: item-level sets all properties; individual overrides persist.
// Merge is the default. Binary properties (no merged version) fall back to imported on merge.

import SwiftUI

// MARK: - Model

enum SingleReviewKind {
    case text
    case picker(options: [String])   // shown as segmented / menu picker
    case binary                       // only existing / imported, no merge version
    case sublist                      // contains nested sub-properties
}

extension SingleReviewKind: Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.text, .text), (.binary, .binary), (.sublist, .sublist): true
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
    init(id: UUID, item: SingleReviewItem, displayName: String, kind: SingleReviewKind, valueKeyPath: KeyPath<any ItemDataAccessable, String>, decision: SingleReviewDecision) {
        self.id = id
        self.item = item
        self.displayName = displayName
        self.kind = kind
        self.valueKeyPath = valueKeyPath
        self.decision = decision
    }
    
    let id: UUID
    let item: SingleReviewItem
    let displayName: String
    let kind: SingleReviewKind
    let valueKeyPath: KeyPath<any ItemDataAccessable, String>
    
    var decision: SingleReviewDecision

    var supportsMerge: Bool { kind != .binary }

    var availableDecisions: [SingleReviewDecision] {
        supportsMerge ? SingleReviewDecision.allCases : [.existing, .imported]
    }
}

@Observable @MainActor
final class SingleReviewEntryProperty: Identifiable {
    init(id: UUID, entry: SingleReviewEntry, displayName: String, kind: SingleReviewKind, valueKeyPath: KeyPath<any EntryDataAccessable, String>, decision: SingleReviewDecision) {
        self.id = id
        self.entry = entry
        self.displayName = displayName
        self.kind = kind
        self.valueKeyPath = valueKeyPath
        self.decision = decision
    }
    
    let id: UUID
    let entry: SingleReviewEntry
    let displayName: String
    let kind: SingleReviewKind
    let valueKeyPath: KeyPath<any EntryDataAccessable, String>
    
    var decision: SingleReviewDecision

    var supportsMerge: Bool { kind != .binary }

    var availableDecisions: [SingleReviewDecision] {
        supportsMerge ? SingleReviewDecision.allCases : [.existing, .imported]
    }
}

@Observable @MainActor
final class SingleReviewReference: Identifiable {
    init(id: UUID, moduleName: String, itemName: String, isResolved: Bool) {
        self.id = id
        self.moduleName = moduleName
        self.itemName = itemName
        self.isResolved = isResolved
    }
    
    let id: UUID
    let moduleName: String
    let itemName: String
    let isResolved: Bool
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
        let item = item.item(for: firstProperty.decision)
        return item[keyPath: firstProperty.valueKeyPath]
    }
    
    var description: String {
        guard properties.count > 1 else { return "No description found" }
        let firstProperty = properties[1]
        let item = item.item(for: firstProperty.decision)
        return item[keyPath: firstProperty.valueKeyPath]
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
    static func from(item: SingleReviewItem) -> SingleItemImportModel {
        var props: [SingleReviewItemProperty] = []

        props.append(SingleReviewItemProperty(id: UUID(), item: item, displayName: "Name", kind: .text, valueKeyPath: \.name, decision: .merge))
        props.append(SingleReviewItemProperty(id: UUID(), item: item, displayName: "Description", kind: .text, valueKeyPath: \.description, decision: .merge))
        props.append(SingleReviewItemProperty(id: UUID(), item: item, displayName: "Tags", kind: .text, valueKeyPath: \.tagLine, decision: .merge))
        props.append(SingleReviewItemProperty(id: UUID(), item: item, displayName: "File", kind: .binary, valueKeyPath: \.fileName, decision: .imported))
        
        // entries — sub-properties paired by name; id = "entry-<entryName>"
        let existingEntries = item.existing?.entries ?? []
        let importedEntries = item.imported?.entries ?? []
        let mergedEntries   = item.merged.entries
        let entries = (existingEntries + importedEntries + mergedEntries)
            .map(\.id)
            .reduce(into: [UUID]()) { if !$0.contains($1) { $0.append($1) } }
            .map { SingleItemImportModel.from(item: item, entryId: $0)}
        
        let references: [SingleReviewReference] = []
        return SingleItemImportModel(item: item, properties: props, entries: entries, references: references)
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
        

        props.append(SingleReviewEntryProperty(id: UUID(), entry: entry, displayName: "Name", kind: .text, valueKeyPath: \.name, decision: .merge))
        props.append(SingleReviewEntryProperty(id: UUID(), entry: entry, displayName: "Content", kind: .text, valueKeyPath: \.content, decision: .merge))
        return SingleEntryImportModel(entry: entry, properties: props, references: [])
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
        existingValue(for: prop) != importedValue(for: prop)
    }

    private func value(from item: any ItemDataAccessable, for prop: SingleReviewItemProperty) -> String? {
        item[keyPath: prop.valueKeyPath].nilIfEmpty
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
private final class PreviewItemModel: ItemDataAccessable, @unchecked Sendable {
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
        model.references = [SingleReviewReference(id: UUID(), moduleName: "Adventure", itemName: "Black Keep", isResolved: false)]
        return model
    }
}

extension ItemDataAccessable {
    var fileName: String {
        fileUrl?.rawValue ?? "No file set"
    }
    
    var tagLine: String {
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
            Image(systemName: reference.isResolved ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(reference.isResolved ? .green : .red)
            VStack(alignment: .leading, spacing: 1) {
                Text(reference.itemName)
                Text(reference.moduleName).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Text(reference.isResolved ? "OK" : "Missing")
                .font(.caption2).foregroundStyle(reference.isResolved ? .green : .red)
        }
        .padding(10)
        .background(reference.isResolved ? Color.green.opacity(0.06) : Color.red.opacity(0.1))
        .clipShape(.rect(cornerRadius: 8))
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
            SingleReviewReference(id: UUID(), moduleName: "Adventure", itemName: "The Vault of Eternity", isResolved: true),
            SingleReviewReference(id: UUID(), moduleName: "Character", itemName: "Elara the Archivist", isResolved: false)
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
            SingleReviewReference(id: UUID(), moduleName: "Map", itemName: "Ashen Reach Region", isResolved: true),
            SingleReviewReference(id: UUID(), moduleName: "Adventure", itemName: "The Mayor's Ledger", isResolved: false),
            SingleReviewReference(id: UUID(), moduleName: "Character", itemName: "Brynn Holt", isResolved: true)
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
                        VC_AccordionRow(model: model, property: prop)
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
                        Text(entry.name).font(.subheadline).bold()
                        Spacer()
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                    Text(entry.content)
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

