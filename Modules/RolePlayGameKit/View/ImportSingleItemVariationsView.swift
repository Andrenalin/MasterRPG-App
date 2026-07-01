//// @copyright André Trettin
////
//// Three layout variations for reviewing one imported item.
//// Decision cascades: item-level sets all properties; individual overrides persist.
//// Merge is the default. Binary properties (no merged version) fall back to imported on merge.
//
//import CoreRPG
//import SwiftUI
//
//// MARK: - Model
//
//enum SingleReviewKind {
//    case text
//    case picker(options: [String])   // shown as segmented / menu picker
//    case binary                       // only existing / imported, no merge version
//    case sublist                      // contains nested sub-properties
//}
//
//extension SingleReviewKind: Equatable {
//    static func == (lhs: Self, rhs: Self) -> Bool {
//        switch (lhs, rhs) {
//        case (.text, .text), (.binary, .binary), (.sublist, .sublist): true
//        case (.picker(let a), .picker(let b)):                          a == b
//        default: false
//        }
//    }
//}
//
//enum SingleReviewDecision: String, CaseIterable, Identifiable {
//    case merge    = "Merge"
//    case existing = "Existing"
//    case imported = "New"
//
//    var id: Self { self }
//
//    var systemImage: String {
//        switch self {
//        case .merge:    "arrow.triangle.merge"
//        case .existing: "clock.arrow.circlepath"
//        case .imported: "tray.and.arrow.down"
//        }
//    }
//
//    var tint: Color {
//        switch self {
//        case .merge:    .blue
//        case .existing: .orange
//        case .imported: .green
//        }
//    }
//
//    var tagline: String {
//        switch self {
//        case .merge:    "Combine both versions"
//        case .existing: "Keep your current data"
//        case .imported: "Replace with imported"
//        }
//    }
//}
//
//@MainActor
//final class SingleReviewItem {
//    init(existing: any ItemDataAccessable, imported: any ItemDataAccessable, merged: any ItemDataAccessable) {
//        self.existing = existing
//        self.imported = imported
//        self.merged = merged
//    }
//    
//    let existing: any ItemDataAccessable
//    let imported: any ItemDataAccessable
//    let merged: any ItemDataAccessable
//    
//    func item(for decision: SingleReviewDecision) -> any ItemDataAccessable {
//        switch decision {
//        case .existing: existing
//        case .imported: imported
//        case .merge: merged
//        }
//    }
//}
//
//@Observable @MainActor
//final class SingleReviewProperty: Identifiable {
//    init(id: UUID, item: SingleReviewItem, displayName: String, kind: SingleReviewKind, valueKeyPath: KeyPath<any ItemDataAccessable, String>, decision: SingleReviewDecision) {
//        self.id = id
//        self.item = item
//        self.displayName = displayName
//        self.kind = kind
//        self.valueKeyPath = valueKeyPath
//        self.decision = decision
//    }
//    
//    let id: UUID
//    let item: SingleReviewItem
//    let displayName: String
//    let kind: SingleReviewKind
//    let valueKeyPath: KeyPath<any ItemDataAccessable, String>
//    
//    var decision: SingleReviewDecision
//
//    var supportsMerge: Bool { kind != .binary }
//
//    var availableDecisions: [SingleReviewDecision] {
//        supportsMerge ? SingleReviewDecision.allCases : [.existing, .imported]
//    }
//}
//
//@Observable @MainActor
//final class SingleReviewReference: Identifiable {
//    init(id: UUID, moduleName: String, itemName: String, isResolved: Bool) {
//        self.id = id
//        self.moduleName = moduleName
//        self.itemName = itemName
//        self.isResolved = isResolved
//    }
//    
//    let id: UUID
//    let moduleName: String
//    let itemName: String
//    let isResolved: Bool
//}
//
//@Observable @MainActor
//final class SingleItemImportModel {
//    init(item: SingleReviewItem, properties: [SingleReviewProperty], entries: [SingleItemImportModel], references: [SingleReviewReference], decision: SingleReviewDecision = .merge) {
//        self.item = item
//        self.properties = properties
//        self.entries = entries
//        self.references = references
//        self.decision = decision
//    }
//    
//    let item: SingleReviewItem
//    let properties: [SingleReviewProperty]
//    let entries: [SingleItemImportModel]
//    var references: [SingleReviewReference]
//    
//    var decision: SingleReviewDecision = .merge
//    
//    func applyItemDecision(_ newDecision: SingleReviewDecision) {
//        decision = newDecision
//        for property in properties {
//            cascade(property, parent: newDecision)
//        }
//        for entry in entries {
//            entry.applyItemDecision(newDecision)
//        }
//    }
//    
//    func setPropertyDecision(_ newDecision: SingleReviewDecision, propertyID: UUID) {
//        seek(in: properties, id: propertyID, to: newDecision)
//        entries.forEach {
//            $0.setPropertyDecision(newDecision, propertyID: propertyID)
//        }
//    }
//    
//    var hasPropertyOverrides: Bool {
//        properties.contains { defaultDecision(for: $0) != $0.decision }
//    }
//    
//    private func cascade(_ prop: SingleReviewProperty, parent: SingleReviewDecision) {
//        prop.decision = defaultDecision(for: prop, given: parent)
//    }
//    
//    private func defaultDecision(for prop: SingleReviewProperty, given parent: SingleReviewDecision? = nil) -> SingleReviewDecision {
//        switch parent ?? decision {
//        case .merge: prop.supportsMerge ? .merge : .imported
//        case .existing: .existing
//        case .imported: .imported
//        }
//    }
//    
//    private func seek(in props: [SingleReviewProperty], id: UUID, to newDecision: SingleReviewDecision) {
//        properties.first(where: { $0.id == id })?.decision = newDecision
//    }
//    
//    var name: String {
//        guard let firstProperty = properties.first else { return "No name found" }
//        let item = item.item(for: firstProperty.decision)
//        return item[keyPath: firstProperty.valueKeyPath]
//    }
//    
//    var description: String {
//        guard properties.count > 1 else { return "No description found" }
//        let firstProperty = properties[1]
//        let item = item.item(for: firstProperty.decision)
//        return item[keyPath: firstProperty.valueKeyPath]
//    }
//    
//    func isChanged(for property: SingleReviewProperty) -> Bool {
//        let hasDescision = properties.first(where: { $0.id == property.id })?.decision ?? .merge
//        return hasDescision != decision
//    }
//}
//
//// MARK: - Preview Data
//
//extension SingleItemImportModel {
//    // MARK: - Real Item Mapping
//
//    // Maps three pre-computed ItemDataAccessable snapshots into a review item.
//    // The UI never computes a merge; existing/imported/merged are provided by the caller
//    // (typically the CRDT merge layer). Pass existing == imported and merged == imported
//    // when there is no prior version.
//    static func from(item: SingleReviewItem) -> SingleItemImportModel {
//        //let item = SingleReviewItem(existing: existing, imported: imported, merged: merged)
//        
//        var props: [SingleReviewProperty] = []
//
//        props.append(SingleReviewProperty(id: UUID(), item: item, displayName: "Name", kind: .text, valueKeyPath: \.name, decision: .merge))
//        props.append(SingleReviewProperty(id: UUID(), item: item, displayName: "Description", kind: .text, valueKeyPath: \.description, decision: .merge))
//        props.append(SingleReviewProperty(id: UUID(), item: item, displayName: "Tags", kind: .text, valueKeyPath: \.tagLine, decision: .merge))
//        props.append(SingleReviewProperty(id: UUID(), item: item, displayName: "File", kind: .binary, valueKeyPath: \.fileName, decision: .imported))
//        
//        // entries — sub-properties paired by name; id = "entry-<entryName>"
//        let existingEntries = item.existing.entries
//        let importedEntries = item.imported.entries
//        let mergedEntries   = item.merged.entries
//        let entries = (existingEntries + importedEntries + mergedEntries)
//            .map(\.id)
//            .reduce(into: [UUID]()) { if !$0.contains($1) { $0.append($1) } }
//            .map { SingleItemImportModel.from(item: item, entryId: $0)}
//        
//        let references = [SingleReviewReference(id: UUID(), moduleName: "Table", itemName: "Loot A", isResolved: false)]
//        return SingleItemImportModel(item: item, properties: props, entries: entries, references: references)
//    }
//    
//    static func from(
//        item: SingleReviewItem,
//        entryId: UUID
//    ) -> SingleItemImportModel {
//        var props: [SingleReviewProperty] = []
//
//        props.append(SingleReviewProperty(id: UUID(), item: item, displayName: "Name", kind: .text, valueKeyPath: \.[entryId].name, decision: .merge))
//        props.append(SingleReviewProperty(id: UUID(), item: item, displayName: "Content", kind: .text, valueKeyPath: \.[entryId].content, decision: .merge))
//        return SingleItemImportModel(item: item, properties: props, entries: [], references: [])
//    }
//}
//
//// MARK: - Display Value Helpers
//
//extension SingleItemImportModel {
//    func existingValue(for prop: SingleReviewProperty) -> String? { value(from: item.item(for: .existing), for: prop) }
//    func importedValue(for prop: SingleReviewProperty) -> String? { value(from: item.item(for: .imported), for: prop) }
//    func mergedValue  (for prop: SingleReviewProperty) -> String? { value(from: item.item(for: .merge),   for: prop) }
//
//    func effectiveValue(for prop: SingleReviewProperty) -> String? {
//        value(from: item.item(for: prop.decision), for: prop)
//    }
//
//    func isChanged(prop: SingleReviewProperty) -> Bool {
//        existingValue(for: prop) != importedValue(for: prop)
//    }
//
//    private func value(from item: any ItemDataAccessable, for prop: SingleReviewProperty) -> String? {
//        item[keyPath: prop.valueKeyPath].nilIfEmpty
//    }
//}
//
//private extension String {
//    var nilIfEmpty: String? { isEmpty ? nil : self }
//}
//
//// MARK: - Preview Data
//
//// MARK: - Preview Models
//
//// A minimal ItemDataAccessable conformance for SwiftUI previews only.
//// Uses EmtpyEntryViewModel (public) as Entry to avoid needing FakeItemModel (internal).
//@Observable
//private final class PreviewItemModel: ItemDataAccessable, @unchecked Sendable {
//    typealias Entry = EmtpyEntryViewModel
//
//    var id: UUID
//    var name: String
//    var category: ItemListCategory
//    var description: String
//    var tags: [String]
//    var displayState: Int
//    var isGroupHiddenToggle: Bool
//    var entries: [EmtpyEntryViewModel]
//    var fileUrl: FileUrl?
//    var parentId: UUID?
//
//    var isGroupHidden: Bool { isGroupHiddenToggle }
//
//    init(id: UUID = UUID(), name: String, category: ItemListCategory = .photo,
//         description: String = "", tags: [String] = [],
//         fileUrl: FileUrl? = nil, entries: [EmtpyEntryViewModel] = []) {
//        self.id = id; self.name = name; self.category = category
//        self.description = description; self.tags = tags
//        self.displayState = 0; self.isGroupHiddenToggle = false
//        self.entries = entries; self.fileUrl = fileUrl; self.parentId = nil
//    }
//
//    subscript(entryId: UUID) -> EmtpyEntryViewModel {
//        get { entries.first { $0.id == entryId } ?? .empty }
//        set { entries = entries.map { $0.id == entryId ? newValue : $0 } }
//    }
//
//    static var empty: PreviewItemModel { PreviewItemModel(name: "") }
//    static func empty(_ id: UUID) -> PreviewItemModel { PreviewItemModel(id: id, name: "") }
//    static var typeId: NetworkModules { .none }
//
//    func copy()      -> PreviewItemModel { PreviewItemModel(id: id, name: name, category: category, description: description, tags: tags, fileUrl: fileUrl, entries: entries) }
//    func duplicate() -> PreviewItemModel { copy() }
//    func filter(filter: String, includeEntries: Bool) -> Bool { true }
//    func isEqual(other: PreviewItemModel) -> Bool { id == other.id }
//    @MainActor func replace(with model: PreviewItemModel) -> Bool { false }
//    static func == (lhs: PreviewItemModel, rhs: PreviewItemModel) -> Bool { lhs.id == rhs.id }
//}
//
//extension SingleItemImportModel {
//    // Preview using .from() so the factory and view helpers are exercised.
//    static var preview: SingleItemImportModel {
//        var bg = EmtpyEntryViewModel.empty;  bg.name = "Background"; bg.content = "Born in Frosthold, trained as a border scout."
//        var notes = EmtpyEntryViewModel.empty; notes.name = "Notes"; notes.content = "Knows the old password for the Black Keep."
//        var bg2 = EmtpyEntryViewModel.empty; bg2.name = "Background"; bg2.content = "Born in Frosthold, now serving aboard The Dread."
//        var ability = EmtpyEntryViewModel.empty; ability.name = "Abilities"; ability.content = "Mist step, shadow blend."
//
//        let existingItem = PreviewItemModel(
//            name: "Mara Venn", category: .photo, description: "A suspicious ranger.",
//            tags: ["npc", "ranger", "suspicious"], entries: [bg, notes]
//        )
//        let importedItem = PreviewItemModel(
//            name: "Mara Venn", category: .photo, description: "A loyal rogue who serves Captain Harl.",
//            tags: ["loyal", "npc", "rogue"],
//            fileUrl: FileUrl(fileId: UUID(), url: URL(filePath: "/portraits/mara.png"), location: .appCloud, module: "photo", relativeUrl: nil),
//            entries: [bg2, ability]
//        )
//        var mergedBg = EmtpyEntryViewModel.empty; mergedBg.name = "Background"; mergedBg.content = "Born in Frosthold, now serving aboard The Dread."
//        let mergedItem = PreviewItemModel(
//            name: "Mara Venn", category: .photo,
//            description: "A loyal rogue who serves Captain Harl.",
//            tags: ["loyal", "npc", "ranger", "rogue", "suspicious"],
//            fileUrl: importedItem.fileUrl,
//            entries: [mergedBg, notes, ability]
//        )
//        let item = SingleReviewItem(existing: existingItem, imported: importedItem, merged: mergedItem)
//        let model = SingleItemImportModel.from(item: item)
//        model.references = [SingleReviewReference(id: UUID(), moduleName: "Adventure", itemName: "Black Keep", isResolved: false)]
//        return model
//    }
//}
//
//extension ItemDataAccessable {
//    var fileName: String {
//        fileUrl?.rawValue ?? "No file set"
//    }
//    
//    var tagLine: String {
//        tags.joined(separator: ",")
//    }
//}
//
//// MARK: - Shared Components
//
//struct SRItemHeader: View {
//    let item: SingleItemImportModel
//
//    var body: some View {
//        VStack(alignment: .leading, spacing: 4) {
//            Text(item.name).font(.title2).bold()
//            Text(item.description).foregroundStyle(.secondary)
//        }
//    }
//}
//
//struct ReviewDecisionCards: View {
//    let model: SingleItemImportModel
//
//    var body: some View {
//        VStack(alignment: .leading, spacing: 12) {
//            SRItemHeader(item: model)
//
//            HStack(spacing: 10) {
//                ForEach(SingleReviewDecision.allCases) { d in
//                    Button {
//                        model.applyItemDecision(d)
//                    } label: {
//                        VStack(spacing: 8) {
//                            Image(systemName: d.systemImage).font(.title2)
//                            Text(d.rawValue).font(.subheadline).bold()
//                            Text(d.tagline).font(.caption2).multilineTextAlignment(.center)
//                                .foregroundStyle(model.decision == d ? d.tint : .secondary)
//                        }
//                        .frame(maxWidth: .infinity)
//                        .padding(.vertical, 14)
//                        .background(model.decision == d ? d.tint.opacity(0.14) : Color.secondary.opacity(0.06))
//                        .foregroundStyle(model.decision == d ? d.tint : .secondary)
//                        .clipShape(.rect(cornerRadius: 14))
//                        .overlay {
//                            RoundedRectangle(cornerRadius: 14)
//                                .strokeBorder(model.decision == d ? d.tint : Color.clear, lineWidth: 2)
//                        }
//                    }
//                    .buttonStyle(.plain)
//                }
//            }
//
//            if model.hasPropertyOverrides {
//                Label("Some properties have custom overrides", systemImage: "slider.horizontal.3")
//                    .font(.caption).foregroundStyle(.secondary)
//            }
//        }
//    }
//}
//
//
//private struct SRDecisionBar: View {
//    let decision: SingleReviewDecision
//    let hasOverrides: Bool
//    let onChange: (SingleReviewDecision) -> Void
//
//    var body: some View {
//        VStack(alignment: .leading, spacing: 6) {
//            HStack(spacing: 8) {
//                ForEach(SingleReviewDecision.allCases) { d in
//                    SRDecisionPill(d: d, isSelected: decision == d) { onChange(d) }
//                }
//            }
//            if hasOverrides {
//                Label("Some properties have custom overrides", systemImage: "slider.horizontal.3")
//                    .font(.caption2).foregroundStyle(.tertiary)
//            }
//        }
//    }
//}
//
//private struct SRDecisionPill: View {
//    let d: SingleReviewDecision
//    let isSelected: Bool
//    let action: () -> Void
//
//    var body: some View {
//        Button(action: action) {
//            Label(d.rawValue, systemImage: d.systemImage)
//                .font(.subheadline)
//                .frame(maxWidth: .infinity)
//                .padding(.vertical, 9)
//                .background(isSelected ? d.tint.opacity(0.16) : Color.secondary.opacity(0.08))
//                .foregroundStyle(isSelected ? d.tint : .secondary)
//                .clipShape(.rect(cornerRadius: 10))
//                .overlay {
//                    RoundedRectangle(cornerRadius: 10)
//                        .strokeBorder(isSelected ? d.tint : Color.clear, lineWidth: 1.5)
//                }
//        }
//        .buttonStyle(.plain)
//    }
//}
//
//// Binary property: only existing / imported, no merge option.
//private struct SRBinaryToggle: View {
//    let model: SingleItemImportModel
//    let property: SingleReviewProperty
//
//    var body: some View {
//        HStack(spacing: 0) {
//            SRBinarySide(
//                label: "Existing", value: model.effectiveValue(for: property),
//                isSelected: property.decision == .existing, tint: .orange
//            ) {
//                property.decision = .existing
//            }
//            Divider().frame(height: 44)
//            SRBinarySide(
//                label: "New", value: model.importedValue(for: property),
//                isSelected: property.decision == .imported, tint: .green
//            ) { property.decision = .imported }
//        }
//        .clipShape(.rect(cornerRadius: 8))
//        .overlay {
//            RoundedRectangle(cornerRadius: 8).strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
//        }
//    }
//}
//
//private struct SRBinarySide: View {
//    let label: String
//    let value: String?
//    let isSelected: Bool
//    let tint: Color
//    let action: () -> Void
//
//    var body: some View {
//        Button(action: action) {
//            VStack(spacing: 3) {
//                Text(label).font(.caption2).bold()
//                Text(value ?? "—").font(.caption).lineLimit(2)
//            }
//            .frame(maxWidth: .infinity).padding(.vertical, 10)
//            .background(isSelected ? tint.opacity(0.16) : Color.secondary.opacity(0.06))
//            .foregroundStyle(isSelected ? tint : .secondary)
//        }
//        .buttonStyle(.plain)
//    }
//}
//
//private struct SRChangeDot: View {
//    let isChanged: Bool
//    var body: some View {
//        if isChanged {
//            Circle().fill(Color.orange).frame(width: 6, height: 6)
//        }
//    }
//}
//
//private struct SRReferenceRow: View {
//    let reference: SingleReviewReference
//
//    var body: some View {
//        HStack {
//            Image(systemName: reference.isResolved ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
//                .foregroundStyle(reference.isResolved ? .green : .red)
//            VStack(alignment: .leading, spacing: 1) {
//                Text(reference.itemName)
//                Text(reference.moduleName).font(.caption2).foregroundStyle(.secondary)
//            }
//            Spacer()
//            Text(reference.isResolved ? "OK" : "Missing")
//                .font(.caption2).foregroundStyle(reference.isResolved ? .green : .red)
//        }
//        .padding(10)
//        .background(reference.isResolved ? Color.green.opacity(0.06) : Color.red.opacity(0.1))
//        .clipShape(.rect(cornerRadius: 8))
//    }
//}
//
//// MARK: - VA: Column Compare
////
//// Three-column grid: Existing | Active | Imported for every property.
//// Changed properties get a warm background tint. Override pickers appear inline.
//// Binary → two-button toggle. Enum → segmented. Sublist → expandable block.
//
//struct SingleItemReviewVA_ColumnCompare: View {
//    let model: SingleItemImportModel
//
//    var body: some View {
//        ScrollView {
//            VStack(alignment: .leading, spacing: 20) {
//                ReviewDecisionCards(model: model)
//
//                if !model.references.isEmpty {
//                    VStack(alignment: .leading, spacing: 6) {
//                        Text("References").font(.headline)
//                        ForEach(model.references) { ref in
//                            SRReferenceRow(reference: ref)
//                        }
//                    }
//                }
//
//                VStack(alignment: .leading, spacing: 8) {
//                    VA_ColumnHeaders()
//                    ForEach(model.properties) { prop in
//                        VA_PropertyRow(model: model, property: prop)
//                    }
//                }
//            }
//            .padding()
//        }
//        .navigationTitle(model.name)
//    }
//}
//
//private struct VA_ColumnHeaders: View {
//    var body: some View {
//        HStack {
//            Text("Existing").font(.caption2).bold().foregroundStyle(.orange)
//                .frame(maxWidth: .infinity, alignment: .leading)
//            Text("Active").font(.caption2).bold().foregroundStyle(.blue)
//                .frame(maxWidth: .infinity, alignment: .center)
//            Text("Imported").font(.caption2).bold().foregroundStyle(.green)
//                .frame(maxWidth: .infinity, alignment: .trailing)
//        }
//        .padding(.horizontal, 12)
//    }
//}
//
//private struct VA_PropertyRow: View {
//    let model: SingleItemImportModel
//    let property: SingleReviewProperty
//
//    var body: some View {
//        VStack(alignment: .leading, spacing: 0) {
//            HStack(spacing: 5) {
//                SRChangeDot(isChanged: property.decision != model.decision)
//                Text(property.displayName).font(.subheadline).bold()
//                if !property.supportsMerge {
//                    Text("binary").font(.caption2).foregroundStyle(.secondary)
//                        .padding(.horizontal, 5).padding(.vertical, 1)
//                        .background(Color.secondary.opacity(0.12)).clipShape(.capsule)
//                }
//            }
//            .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 6)
//
//            switch property.kind {
//            case .binary:
//                SRBinaryToggle(model: model, property: property)
//                    .padding(.horizontal, 12).padding(.bottom, 10)
//            default:
//                VA_ThreeColumnValue(model: model, property: property)
//                    .padding(.horizontal, 12).padding(.bottom, 10)
//            }
//        }
//        .background(property.decision != model.decision ? Color.orange.opacity(0.05) : Color.secondary.opacity(0.04))
//        .clipShape(.rect(cornerRadius: 10))
//    }
//}
//
//private struct VA_ThreeColumnValue: View {
//    let model: SingleItemImportModel
//    let property: SingleReviewProperty
//
//    var body: some View {
//        VStack(spacing: 8) {
//            HStack(alignment: .top, spacing: 6) {
//                VA_Cell(value: model.existingValue(for: property), tint: .orange,
//                        isActive: property.decision == .existing, label: nil)
//                VA_Cell(value: model.mergedValue(for: property), tint: property.decision.tint,
//                        isActive: property.decision == .merge, label: property.decision.rawValue)
//                VA_Cell(value: model.importedValue(for: property), tint: .green,
//                        isActive: property.decision == .imported, label: nil)
//            }
//
//            if case .picker(let options) = property.kind {
//                Picker("", selection: Binding(
//                    get: { model.effectiveValue(for: property) ?? "" },
//                    set: { _ in }
//                )) {
//                    ForEach(options, id: \.self) { opt in Text(opt).tag(opt) }
//                }
//                .pickerStyle(.segmented)
//                .disabled(true)
//            }
//
//            // Override picker only when values differ
//            if model.isChanged(for: property) {
//                Picker("Override", selection: Binding(
//                    get: { property.decision },
//                    set: { model.setPropertyDecision($0, propertyID: property.id) }
//                )) {
//                    ForEach(property.availableDecisions) { d in
//                        Label(d.rawValue, systemImage: d.systemImage).tag(d)
//                    }
//                }
//                .pickerStyle(.segmented)
//            }
//        }
//    }
//}
//
//private struct VA_Cell: View {
//    let value: String?
//    let tint: Color
//    let isActive: Bool
//    let label: String?
//
//    var body: some View {
//        VStack(alignment: .leading, spacing: 3) {
//            if let label {
//                Text(label).font(.caption2).bold().foregroundStyle(tint)
//            }
//            Text(value ?? "—")
//                .font(.caption).lineLimit(3)
//                .frame(maxWidth: .infinity, alignment: .leading)
//        }
//        .padding(8)
//        .background(isActive ? tint.opacity(0.12) : Color.secondary.opacity(0.05))
//        .foregroundStyle(isActive ? tint : .secondary)
//        .clipShape(.rect(cornerRadius: 7))
//    }
//}
//
////private struct VA_SublistBlock: View {
////    let property: SingleReviewProperty
////    @Bindable var model: SingleItemImportModel
////    @State private var isExpanded = true
////
////    var body: some View {
////        VStack(alignment: .leading, spacing: 6) {
////            Button {
////                withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
////            } label: {
////                HStack {
////                    Text("\(property.subproperties.count) sub-items")
////                        .font(.caption).foregroundStyle(.secondary)
////                    Spacer()
////                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
////                        .font(.caption2).foregroundStyle(.secondary)
////                }
////            }
////            .buttonStyle(.plain)
////
////            if isExpanded {
////                VStack(spacing: 4) {
////                    ForEach(property.subproperties) { sub in
////                        VA_PropertyRow(property: sub, model: model)
////                    }
////                }
////            }
////        }
////    }
////}
//
//#Preview("VA · Column Compare") {
//    NavigationStack { SingleItemReviewVA_ColumnCompare(model: .preview) }
//}
//
//// MARK: - VB: Form Reveal
////
//// A standard List/Form showing the current effective value per property.
//// Orange dot marks changed properties. Tap any changed row to reveal all three
//// versions with decision buttons. Binary → two-button toggle inline. Enum →
//// segmented control. Sublist → nested rows with per-item mini picker.
//
////struct SingleItemReviewVB_FormReveal: View {
////    @Bindable var model: SingleItemImportModel
////    @State private var expandedIDs: Set<String> = []
////
////    var body: some View {
////        List {
////            Section {
////                ReviewDecisionCards(model: model)
////                .listRowSeparator(.hidden)
////            }
////
////            if !model.item.references.isEmpty {
////                Section("References") {
////                    ForEach(model.item.references) { ref in
////                        SRReferenceRow(reference: ref).listRowInsets(.init())
////                    }
////                }
////            }
////
////            Section("Properties") {
////                ForEach(model.item.properties) { prop in
////                    VB_PropertyRow(
////                        property: prop,
////                        isExpanded: Binding(
////                            get: { expandedIDs.contains(prop.id) },
////                            set: { expanded in
////                                withAnimation(.easeInOut(duration: 0.18)) {
////                                    if expanded { expandedIDs.insert(prop.id) }
////                                    else        { expandedIDs.remove(prop.id) }
////                                }
////                            }
////                        ),
////                        model: model
////                    )
////                }
////            }
////        }
////        .listStyle(.insetGrouped)
////        .navigationTitle(model.item.name)
////    }
////}
////
////private struct VB_PropertyRow: View {
////    let property: SingleReviewProperty
////    @Binding var isExpanded: Bool
////    @Bindable var model: SingleItemImportModel
////
////    var body: some View {
////        VStack(alignment: .leading, spacing: 0) {
////            // Collapsed header — always visible
////            Button {
////                guard property.decision != model.decision else { return }
////                isExpanded.toggle()
////            } label: {
////                HStack {
////                    SRChangeDot(isChanged: property.decision != model.decision)
////                    Text(property.name)
////                    Spacer()
////                    if let value = property.effectiveValue {
////                        Text(value)
////                            .font(.subheadline)
////                            .foregroundStyle(property.decision != model.decision ? property.decision.tint : .secondary)
////                            .lineLimit(1)
////                    }
////                    if property.isChanged {
////                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
////                            .font(.caption2).foregroundStyle(.secondary)
////                    }
////                }
////            }
////            .buttonStyle(.plain)
////
////            // Expanded detail
////            if isExpanded {
////                VStack(alignment: .leading, spacing: 10) {
////                    Divider().padding(.top, 8)
////
////                    switch property.kind {
////                    case .binary:
////                        SRBinaryToggle(property: property) { d in
////                            model.setPropertyDecision(d, propertyID: property.id)
////                        }
////                    case .sublist:
////                        VB_SublistDetail(property: property, model: model)
////                    default:
////                        VB_DecisionOptions(property: property, model: model)
////                    }
////                }
////                .padding(.top, 4).padding(.bottom, 8)
////                .transition(.opacity.combined(with: .move(edge: .top)))
////            }
////        }
////        .padding(.vertical, 4)
////    }
////}
////
////private struct VB_DecisionOptions: View {
////    let property: SingleReviewProperty
////    @Bindable var model: SingleItemImportModel
////
////    var body: some View {
////        VStack(spacing: 6) {
////            ForEach(property.availableDecisions) { d in
////                Button {
////                    model.setPropertyDecision(d, propertyID: property.id)
////                } label: {
////                    HStack(spacing: 10) {
////                        Image(systemName: d.systemImage).foregroundStyle(d.tint)
////                            .frame(width: 22)
////                        VStack(alignment: .leading, spacing: 1) {
////                            Text(d.rawValue).bold()
////                            Text(valueLabel(for: d)).font(.caption).foregroundStyle(.secondary)
////                                .lineLimit(2)
////                        }
////                        Spacer()
////                        if property.decision == d {
////                            Image(systemName: "checkmark.circle.fill").foregroundStyle(d.tint)
////                        }
////                    }
////                    .padding(10)
////                    .background(property.decision == d ? d.tint.opacity(0.12) : Color.secondary.opacity(0.06))
////                    .clipShape(.rect(cornerRadius: 9))
////                }
////                .buttonStyle(.plain)
////            }
////
////            if case .picker(let options) = property.kind {
////                Picker("Active value", selection: .constant(property.effectiveValue ?? "")) {
////                    ForEach(options, id: \.self) { opt in Text(opt).tag(opt) }
////                }
////                .pickerStyle(.segmented)
////                .disabled(true)
////                .padding(.top, 4)
////            }
////        }
////    }
////
////    private func valueLabel(for d: SingleReviewDecision) -> String {
////        switch d {
////        case .merge:    property.merged ?? "—"
////        case .existing: property.existing ?? "Not present locally"
////        case .imported: property.imported ?? "Not in import"
////        }
////    }
////}
////
////private struct VB_SublistDetail: View {
////    let property: SingleReviewProperty
////    @Bindable var model: SingleItemImportModel
////
////    var body: some View {
////        VStack(spacing: 6) {
////            ForEach(property.subproperties) { sub in
////                HStack(spacing: 8) {
////                    VStack(alignment: .leading, spacing: 2) {
////                        HStack(spacing: 4) {
////                            SRChangeDot(isChanged: sub.isChanged)
////                            Text(sub.name).font(.subheadline)
////                        }
////                        if sub.isChanged {
////                            HStack(spacing: 4) {
////                                Text(sub.existing ?? "—").font(.caption).foregroundStyle(.orange)
////                                Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.secondary)
////                                Text(sub.imported ?? "—").font(.caption).foregroundStyle(.green)
////                            }
////                        } else {
////                            Text(sub.effectiveValue ?? "—").font(.caption).foregroundStyle(.secondary)
////                        }
////                    }
////                    Spacer()
////                    if case .binary = sub.kind {
////                        Menu {
////                            ForEach(sub.availableDecisions) { d in
////                                Button {
////                                    model.setPropertyDecision(d, propertyID: sub.id)
////                                } label: {
////                                    Label(d.rawValue, systemImage: d.systemImage)
////                                }
////                            }
////                        } label: {
////                            Label(sub.decision.rawValue, systemImage: sub.decision.systemImage)
////                                .font(.caption)
////                                .foregroundStyle(sub.decision.tint)
////                        }
////                    } else if sub.isChanged {
////                        Picker("", selection: Binding(
////                            get: { sub.decision },
////                            set: { model.setPropertyDecision($0, propertyID: sub.id) }
////                        )) {
////                            ForEach(sub.availableDecisions) { d in Text(d.rawValue).tag(d) }
////                        }
////                        .labelsHidden().fixedSize()
////                    }
////                }
////                .padding(10)
////                .background(sub.isChanged ? Color.orange.opacity(0.05) : Color.secondary.opacity(0.04))
////                .clipShape(.rect(cornerRadius: 8))
////            }
////        }
////    }
////}
////
////#Preview("VB · Form Reveal") {
////    NavigationStack { SingleItemReviewVB_FormReveal(model: .preview) }
////}
//
////// MARK: - VC: Diff Strip
//////
////// Large item-level decision cards with taglines at the top.
////// Properties appear as diff rows: Existing ◀ ● ▶ Imported, with a circular
////// cycle-button in the centre that advances through available decisions.
////// The active side is saturated; the inactive side is dimmed.
////// Binary → explicit two-button toggle. Merge winner shown in a blue banner below.
////// Sublist → collapsible with the same cycle-button pattern per sub-row.
////
////struct SingleItemReviewVC_DiffStrip: View {
////    @Bindable var model: SingleItemImportModel
////
////    var body: some View {
////        ScrollView {
////            VStack(alignment: .leading, spacing: 20) {
////                ReviewDecisionCards(model: model)
////
////                if !model.item.references.isEmpty {
////                    VStack(alignment: .leading, spacing: 6) {
////                        Text("References").font(.headline)
////                        ForEach(model.item.references) { ref in SRReferenceRow(reference: ref) }
////                    }
////                }
////
////                VStack(alignment: .leading, spacing: 6) {
////                    VC_ColumnHeader()
////                    ForEach(model.item.properties) { prop in
////                        VC_PropertyRow(property: prop, model: model)
////                    }
////                }
////            }
////            .padding()
////        }
////        .navigationTitle(model.item.name)
////    }
////}
////
////private struct VC_ColumnHeader: View {
////    var body: some View {
////        HStack {
////            Text("Existing").font(.caption2).bold().foregroundStyle(.orange)
////                .frame(maxWidth: .infinity, alignment: .leading)
////            Spacer().frame(width: 40)
////            Text("Imported").font(.caption2).bold().foregroundStyle(.green)
////                .frame(maxWidth: .infinity, alignment: .trailing)
////        }
////        .padding(.horizontal, 4)
////    }
////}
////
////private struct VC_PropertyRow: View {
////    let property: SingleReviewProperty
////    @Bindable var model: SingleItemImportModel
////
////    var body: some View {
////        VStack(alignment: .leading, spacing: 6) {
////            HStack(spacing: 5) {
////                SRChangeDot(isChanged: property.isChanged)
////                Text(property.name).font(.caption2).bold().foregroundStyle(.secondary)
////                if !property.supportsMerge && property.kind != .sublist {
////                    Text("binary").font(.caption2).foregroundStyle(.tertiary)
////                        .padding(.horizontal, 4).padding(.vertical, 1)
////                        .background(Color.secondary.opacity(0.1)).clipShape(.capsule)
////                }
////            }
////
////            switch property.kind {
////            case .sublist:
////                VC_SublistBlock(property: property, model: model)
////            case .binary:
////                SRBinaryToggle(property: property) { d in
////                    model.setPropertyDecision(d, propertyID: property.id)
////                }
////            default:
////                VC_DiffRow(property: property, model: model)
////            }
////        }
////        .padding(10)
////        .background(property.decision != model.decision ? Color.orange.opacity(0.05) : Color.clear)
////        .clipShape(.rect(cornerRadius: 10))
////        .overlay {
////            RoundedRectangle(cornerRadius: 10)
////                .strokeBorder(Color.secondary.opacity(property.decision != model.decision ? 0.12 : 0), lineWidth: 1)
////        }
////    }
////}
////
////private struct VC_DiffRow: View {
////    let property: SingleReviewProperty
////    @Bindable var model: SingleItemImportModel
////
////    var body: some View {
////        VStack(spacing: 6) {
////            HStack(spacing: 6) {
////                VC_Side(value: property.existing, tint: .orange,
////                        isWinner: property.decision == .existing)
////
////                VC_CycleButton(decision: property.decision,
////                               available: property.availableDecisions) { next in
////                    model.setPropertyDecision(next, propertyID: property.id)
////                }
////
////                VC_Side(value: property.imported, tint: .green,
////                        isWinner: property.decision == .imported)
////            }
////
////            // Merged result banner
////            if property.decision == .merge, let merged = property.merged {
////                HStack(spacing: 6) {
////                    Image(systemName: "arrow.triangle.merge").font(.caption2).foregroundStyle(.blue)
////                    Text(merged).font(.caption).foregroundStyle(.blue)
////                    Spacer()
////                }
////                .padding(8)
////                .background(Color.blue.opacity(0.08))
////                .clipShape(.rect(cornerRadius: 7))
////            }
////
////            // Enum override picker
////            if case .picker(_) = property.kind, property.isChanged {
////                Picker("", selection: Binding(
////                    get: { property.decision },
////                    set: { model.setPropertyDecision($0, propertyID: property.id) }
////                )) {
////                    ForEach(property.availableDecisions) { d in Text(d.rawValue).tag(d) }
////                }
////                .pickerStyle(.segmented)
////            }
////        }
////    }
////}
////
////private struct VC_Side: View {
////    let value: String?
////    let tint: Color
////    let isWinner: Bool
////
////    var body: some View {
////        Text(value ?? "—")
////            .font(.caption).lineLimit(3)
////            .frame(maxWidth: .infinity, alignment: .leading)
////            .padding(8)
////            .background(isWinner ? tint.opacity(0.13) : Color.clear)
////            .foregroundStyle(isWinner ? tint : Color.secondary.opacity(0.5))
////            .clipShape(.rect(cornerRadius: 6))
////    }
////}
////
////private struct VC_CycleButton: View {
////    let decision: SingleReviewDecision
////    let available: [SingleReviewDecision]
////    let onNext: (SingleReviewDecision) -> Void
////
////    private var next: SingleReviewDecision {
////        guard let idx = available.firstIndex(of: decision) else { return available[0] }
////        return available[(idx + 1) % available.count]
////    }
////
////    var body: some View {
////        Button {
////            onNext(next)
////        } label: {
////            Image(systemName: decision.systemImage)
////                .font(.subheadline)
////                .frame(width: 38, height: 38)
////                .background(decision.tint.opacity(0.14))
////                .foregroundStyle(decision.tint)
////                .clipShape(.circle)
////        }
////        .buttonStyle(.plain)
////        .accessibilityLabel("Decision: \(decision.rawValue). Tap to cycle.")
////    }
////}
////
////private struct VC_SublistBlock: View {
////    let property: SingleReviewProperty
////    @Bindable var model: SingleItemImportModel
////    @State private var isExpanded = true
////
////    var body: some View {
////        VStack(alignment: .leading, spacing: 6) {
////            Button {
////                withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
////            } label: {
////                HStack {
////                    Text("\(property.subproperties.count) sub-items")
////                        .font(.caption).foregroundStyle(.secondary)
////                    Spacer()
////                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
////                        .font(.caption2).foregroundStyle(.secondary)
////                }
////            }
////            .buttonStyle(.plain)
////
////            if isExpanded {
////                VStack(spacing: 4) {
////                    ForEach(property.subproperties) { sub in
////                        VStack(alignment: .leading, spacing: 4) {
////                            HStack(spacing: 4) {
////                                SRChangeDot(isChanged: sub.isChanged)
////                                Text(sub.name).font(.caption2).bold().foregroundStyle(.secondary)
////                            }
////                            if case .binary = sub.kind {
////                                SRBinaryToggle(property: sub) { d in
////                                    model.setPropertyDecision(d, propertyID: sub.id)
////                                }
////                            } else {
////                                HStack(spacing: 6) {
////                                    VC_Side(value: sub.existing, tint: .orange,
////                                            isWinner: sub.decision == .existing)
////                                    VC_CycleButton(decision: sub.decision,
////                                                   available: sub.availableDecisions) { d in
////                                        model.setPropertyDecision(d, propertyID: sub.id)
////                                    }
////                                    VC_Side(value: sub.imported, tint: .green,
////                                            isWinner: sub.decision == .imported)
////                                }
////                                if sub.decision == .merge, let merged = sub.merged {
////                                    HStack(spacing: 5) {
////                                        Image(systemName: "arrow.triangle.merge").font(.caption2)
////                                        Text(merged).font(.caption)
////                                    }
////                                    .foregroundStyle(.blue)
////                                    .padding(6)
////                                    .background(Color.blue.opacity(0.08))
////                                    .clipShape(.rect(cornerRadius: 6))
////                                }
////                            }
////                        }
////                        .padding(8)
////                        .background(sub.isChanged ? Color.orange.opacity(0.05) : Color.secondary.opacity(0.04))
////                        .clipShape(.rect(cornerRadius: 7))
////                    }
////                }
////            }
////        }
////    }
////}
////
////#Preview("VC · Diff Strip") {
////    NavigationStack { SingleItemReviewVC_DiffStrip(model: .preview) }
////}
