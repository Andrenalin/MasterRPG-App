// @copyright André Trettin

import Observation
import SwiftUI

@MainActor
@Observable
final class ImportReviewPrototypeModel {
    var modules: [ImportReviewPrototypeModule]
    var selectedModuleID: ImportReviewPrototypeModule.ID?
    var selectedItemID: ImportReviewPrototypeItem.ID?

    init(modules: [ImportReviewPrototypeModule]) {
        self.modules = modules
        self.selectedModuleID = modules.first?.id
        self.selectedItemID = modules.first?.reviewItems.first?.id
    }

    var selectedModule: ImportReviewPrototypeModule? {
        modules.first { $0.id == selectedModuleID }
    }

    var selectedItem: ImportReviewPrototypeItem? {
        selectedModule?.reviewItems.first { $0.id == selectedItemID }
    }

    func select(moduleID: ImportReviewPrototypeModule.ID) {
        selectedModuleID = moduleID
        selectedItemID = modules.first { $0.id == moduleID }?.reviewItems.first?.id
    }

    func select(itemID: ImportReviewPrototypeItem.ID) {
        selectedItemID = itemID
    }

    func selectDependency(_ dependency: ImportReviewPrototypeReference) {
        selectedModuleID = dependency.moduleID
        selectedItemID = dependency.itemID
    }

    func setDecision(_ decision: ImportReviewPrototypeDecision, for itemID: ImportReviewPrototypeItem.ID) {
        guard let itemLocation = itemLocation(for: itemID) else { return }
        modules[itemLocation.moduleIndex].reviewItems[itemLocation.itemIndex].decision = decision
    }

    func setPropertyDecision(_ decision: ImportReviewPrototypeDecision, propertyID: ImportReviewPrototypeProperty.ID, itemID: ImportReviewPrototypeItem.ID) {
        guard let itemLocation = itemLocation(for: itemID),
              let propertyIndex = modules[itemLocation.moduleIndex].reviewItems[itemLocation.itemIndex].properties.firstIndex(where: { $0.id == propertyID }) else {
            return
        }

        modules[itemLocation.moduleIndex].reviewItems[itemLocation.itemIndex].properties[propertyIndex].decision = decision
    }

    private func itemLocation(for itemID: ImportReviewPrototypeItem.ID) -> (moduleIndex: Int, itemIndex: Int)? {
        for moduleIndex in modules.indices {
            if let itemIndex = modules[moduleIndex].reviewItems.firstIndex(where: { $0.id == itemID }) {
                return (moduleIndex, itemIndex)
            }
        }

        return nil
    }
}

struct ImportReviewPrototypeModule: Identifiable, Hashable {
    let id: String
    let name: String
    var reviewItems: [ImportReviewPrototypeItem]
}

struct ImportReviewPrototypeItem: Identifiable, Hashable {
    enum ChangeKind: String, CaseIterable, Hashable {
        case added = "Added"
        case different = "Different"
    }

    let id: String
    let name: String
    let summary: String
    let kind: ChangeKind
    let existingStatus: String
    let importedStatus: String
    let mergedStatus: String
    let references: [ImportReviewPrototypeReference]
    var decision: ImportReviewPrototypeDecision
    var properties: [ImportReviewPrototypeProperty]

    var hasBlockingReference: Bool {
        references.contains { !$0.isSelected }
    }
}

struct ImportReviewPrototypeProperty: Identifiable, Hashable {
    let id: String
    let name: String
    let existingValue: String
    let importedValue: String
    let mergedValue: String
    var decision: ImportReviewPrototypeDecision
}

struct ImportReviewPrototypeReference: Identifiable, Hashable {
    let id: String
    let moduleID: String
    let itemID: String
    let moduleName: String
    let itemName: String
    let isSelected: Bool
}

enum ImportReviewPrototypeDecision: String, CaseIterable, Identifiable, Hashable {
    case merge = "Merge"
    case existing = "Existing"
    case imported = "New"
    case skip = "Skip"

    var id: Self { self }

    var systemImage: String {
        switch self {
        case .merge:
            "arrow.triangle.merge"
        case .existing:
            "clock.arrow.circlepath"
        case .imported:
            "tray.and.arrow.down"
        case .skip:
            "slash.circle"
        }
    }
}

struct ImportReviewPrototypeView: View {
    @Bindable var model: ImportReviewPrototypeModel
    let title: String

    init(model: ImportReviewPrototypeModel, title: String = "Import Review") {
        self.model = model
        self.title = title
    }

    var body: some View {
        NavigationSplitView {
            ImportReviewModuleListView(model: model)
                .navigationTitle(title)
        } content: {
            ImportReviewItemListView(model: model)
                .navigationTitle(model.selectedModule?.name ?? "Items")
        } detail: {
            ImportReviewDetailView(model: model)
        }
    }
}

private struct ImportReviewModuleListView: View {
    @Bindable var model: ImportReviewPrototypeModel

    var body: some View {
        List(selection: $model.selectedModuleID) {
            ForEach(model.modules) { module in
                Button {
                    model.select(moduleID: module.id)
                } label: {
                    ImportReviewModuleRow(module: module)
                }
                .buttonStyle(.plain)
                .tag(module.id)
            }
        }
        .accessibilityLabel("Import modules")
    }
}

private struct ImportReviewModuleRow: View {
    let module: ImportReviewPrototypeModule

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(module.name)
                    .bold()
                Spacer()
                Text("\(module.reviewItems.count)")
                    .foregroundStyle(.secondary)
            }

            HStack {
                ImportReviewCountLabel(title: "Added", count: addedCount, tint: .green)
                ImportReviewCountLabel(title: "Different", count: differentCount, tint: .orange)
                if blockedCount > 0 {
                    ImportReviewCountLabel(title: "Needs review", count: blockedCount, tint: .red)
                }
            }
            .font(.caption)
        }
        .padding(.vertical, 4)
    }

    private var addedCount: Int {
        module.reviewItems.filter { $0.kind == .added }.count
    }

    private var differentCount: Int {
        module.reviewItems.filter { $0.kind == .different }.count
    }

    private var blockedCount: Int {
        module.reviewItems.filter(\.hasBlockingReference).count
    }
}

private struct ImportReviewItemListView: View {
    @Bindable var model: ImportReviewPrototypeModel

    var body: some View {
        List(selection: $model.selectedItemID) {
            if let module = model.selectedModule {
                Section {
                    ForEach(module.reviewItems) { item in
                        Button {
                            model.select(itemID: item.id)
                        } label: {
                            ImportReviewItemRow(item: item)
                        }
                        .buttonStyle(.plain)
                        .tag(item.id)
                    }
                } header: {
                    Text(module.name)
                }
            }
        }
        .accessibilityLabel("Import review items")
    }
}

private struct ImportReviewItemRow: View {
    let item: ImportReviewPrototypeItem

    var body: some View {
        VStack(alignment: .leading) {
            HStack(alignment: .firstTextBaseline) {
                Label(item.kind.rawValue, systemImage: item.kind == .added ? "plus.circle" : "exclamationmark.triangle")
                    .foregroundStyle(item.kind == .added ? .green : .orange)
                Spacer()
                ImportReviewDecisionBadge(decision: item.decision)
            }

            Text(item.name)
                .bold()

            Text(item.summary)
                .foregroundStyle(.secondary)

            if item.hasBlockingReference {
                Label("Required item is not selected", systemImage: "link.badge.plus")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 6)
    }
}

private struct ImportReviewDetailView: View {
    @Bindable var model: ImportReviewPrototypeModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let item = model.selectedItem {
                    ImportReviewDetailHeader(item: item) { decision in
                        model.setDecision(decision, for: item.id)
                    }

                    ImportReviewStatusComparison(item: item)

                    ImportReviewReferenceSection(item: item) { reference in
                        model.selectDependency(reference)
                    }

                    ImportReviewPropertySection(item: item) { propertyID, decision in
                        model.setPropertyDecision(decision, propertyID: propertyID, itemID: item.id)
                    }
                } else {
                    ContentUnavailableView("Select an item", systemImage: "list.bullet.rectangle")
                }
            }
            .padding()
        }
        .navigationTitle(model.selectedItem?.name ?? "Review Detail")
    }
}

private struct ImportReviewDetailHeader: View {
    let item: ImportReviewPrototypeItem
    let onDecisionChange: (ImportReviewPrototypeDecision) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading) {
                    Text(item.name)
                        .font(.title2)
                        .bold()
                    Text(item.summary)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                ImportReviewDecisionBadge(decision: item.decision)
            }

            Picker("Item decision", selection: Binding(
                get: { item.decision },
                set: onDecisionChange
            )) {
                ForEach(ImportReviewPrototypeDecision.allCases) { decision in
                    Label(decision.rawValue, systemImage: decision.systemImage)
                        .tag(decision)
                }
            }
            .pickerStyle(.segmented)
        }
        .accessibilityElement(children: .contain)
    }
}

private struct ImportReviewStatusComparison: View {
    let item: ImportReviewPrototypeItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Status")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    ImportReviewStatusColumn(title: "Merged", value: item.mergedStatus, tint: .blue)
                    ImportReviewStatusColumn(title: "Existing", value: item.existingStatus, tint: .secondary)
                    ImportReviewStatusColumn(title: "New imported", value: item.importedStatus, tint: .green)
                }
            }
        }
    }
}

private struct ImportReviewStatusColumn: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(tint)
            Text(value)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(.thinMaterial)
        .clipShape(.rect(cornerRadius: 8))
    }
}

private struct ImportReviewReferenceSection: View {
    let item: ImportReviewPrototypeItem
    let onReferenceSelected: (ImportReviewPrototypeReference) -> Void

    var body: some View {
        if !item.references.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("References")
                    .font(.headline)

                ForEach(item.references) { reference in
                    ImportReviewReferenceRow(reference: reference, onReferenceSelected: onReferenceSelected)
                }
            }
        }
    }
}

private struct ImportReviewReferenceRow: View {
    let reference: ImportReviewPrototypeReference
    let onReferenceSelected: (ImportReviewPrototypeReference) -> Void

    var body: some View {
        Button {
            onReferenceSelected(reference)
        } label: {
            HStack {
                Label(reference.itemName, systemImage: reference.isSelected ? "checkmark.circle" : "exclamationmark.triangle")
                Spacer()
                Text(reference.moduleName)
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(reference.isSelected ? Color.primary : Color.red)
            .padding()
            .background(reference.isSelected ? Color.secondary.opacity(0.08) : Color.red.opacity(0.12))
            .clipShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityHint(reference.isSelected ? "Reference is selected" : "Opens the referenced item so it can be selected")
    }
}

private struct ImportReviewPropertySection: View {
    let item: ImportReviewPrototypeItem
    let onDecisionChange: (ImportReviewPrototypeProperty.ID, ImportReviewPrototypeDecision) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Property choices")
                .font(.headline)

            ForEach(item.properties) { property in
                ImportReviewPropertyRow(property: property) { decision in
                    onDecisionChange(property.id, decision)
                }
            }
        }
    }
}

private struct ImportReviewPropertyRow: View {
    let property: ImportReviewPrototypeProperty
    let onDecisionChange: (ImportReviewPrototypeDecision) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(property.name)
                    .bold()
                Spacer()
                ImportReviewDecisionBadge(decision: property.decision)
            }

            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow {
                    ImportReviewPropertyValue(title: "Merged", value: property.mergedValue, tint: .blue)
                    ImportReviewPropertyValue(title: "Existing", value: property.existingValue, tint: .secondary)
                    ImportReviewPropertyValue(title: "New", value: property.importedValue, tint: .green)
                }
            }

            Picker("Property decision", selection: Binding(
                get: { property.decision },
                set: onDecisionChange
            )) {
                ForEach(ImportReviewPrototypeDecision.allCases) { decision in
                    Text(decision.rawValue)
                        .tag(decision)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding()
        .background(.thinMaterial)
        .clipShape(.rect(cornerRadius: 8))
    }
}

private struct ImportReviewPropertyValue: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(tint)
            Text(value)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ImportReviewDecisionBadge: View {
    let decision: ImportReviewPrototypeDecision

    var body: some View {
        Label(decision.rawValue, systemImage: decision.systemImage)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.thinMaterial)
            .clipShape(.capsule)
    }
}

private struct ImportReviewCountLabel: View {
    let title: String
    let count: Int
    let tint: Color

    var body: some View {
        Label("\(count) \(title)", systemImage: "circle.fill")
            .foregroundStyle(tint)
    }
}

struct ImportReviewPrototypeComparisonView: View {
    var body: some View {
        HStack(spacing: 0) {
            ImportReviewPrototypeView(model: .preview, title: "Balanced")
            Divider()
            ImportReviewPrototypeView(model: .dependencyWarningPreview, title: "References")
            Divider()
            ImportReviewPrototypeView(model: .propertyFocusedPreview, title: "Properties")
        }
    }
}

extension ImportReviewPrototypeModel {
    static var preview: ImportReviewPrototypeModel {
        ImportReviewPrototypeModel(modules: .preview)
    }

    static var dependencyWarningPreview: ImportReviewPrototypeModel {
        let model = ImportReviewPrototypeModel(modules: .preview)
        model.selectedModuleID = ImportReviewPreviewID.mapModule
        model.selectedItemID = ImportReviewPreviewID.secretDoor
        return model
    }

    static var propertyFocusedPreview: ImportReviewPrototypeModel {
        let model = ImportReviewPrototypeModel(modules: .preview)
        model.selectedModuleID = ImportReviewPreviewID.characterModule
        model.selectedItemID = ImportReviewPreviewID.mara
        return model
    }
}

private extension Array where Element == ImportReviewPrototypeModule {
    static var preview: [ImportReviewPrototypeModule] {
        [
            ImportReviewPrototypeModule(
                id: ImportReviewPreviewID.adventureModule,
                name: "Adventure",
                reviewItems: [
                    ImportReviewPrototypeItem(
                        id: ImportReviewPreviewID.blackKeep,
                        name: "Black Keep",
                        summary: "Imported outline adds two encounters and updates the final scene.",
                        kind: .different,
                        existingStatus: "5 scenes, local notes kept",
                        importedStatus: "7 scenes, new finale",
                        mergedStatus: "7 scenes, local notes plus imported finale",
                        references: [],
                        decision: .merge,
                        properties: [
                            ImportReviewPrototypeProperty(id: ImportReviewPreviewID.blackKeepTitle, name: "Title", existingValue: "Black Keep", importedValue: "The Black Keep", mergedValue: "Black Keep", decision: .existing),
                            ImportReviewPrototypeProperty(id: ImportReviewPreviewID.blackKeepSummary, name: "Summary", existingValue: "A haunted ruin near the coast.", importedValue: "A fortress with a sealed gate and ghost captain.", mergedValue: "A haunted coastal fortress with a sealed gate.", decision: .merge),
                            ImportReviewPrototypeProperty(id: ImportReviewPreviewID.blackKeepNotes, name: "Player notes", existingValue: "Mira knows the old password.", importedValue: "No notes", mergedValue: "Mira knows the old password.", decision: .existing),
                        ]
                    ),
                    ImportReviewPrototypeItem(
                        id: ImportReviewPreviewID.frozenVault,
                        name: "Frozen Vault",
                        summary: "New adventure from the import package.",
                        kind: .added,
                        existingStatus: "Not in library",
                        importedStatus: "3 scenes, 1 map, 2 tables",
                        mergedStatus: "Ready to add",
                        references: [],
                        decision: .imported,
                        properties: [
                            ImportReviewPrototypeProperty(id: ImportReviewPreviewID.frozenVaultTitle, name: "Title", existingValue: "None", importedValue: "Frozen Vault", mergedValue: "Frozen Vault", decision: .imported),
                            ImportReviewPrototypeProperty(id: ImportReviewPreviewID.frozenVaultDifficulty, name: "Difficulty", existingValue: "None", importedValue: "High", mergedValue: "High", decision: .imported),
                        ]
                    ),
                ]
            ),
            ImportReviewPrototypeModule(
                id: ImportReviewPreviewID.characterModule,
                name: "Character",
                reviewItems: [
                    ImportReviewPrototypeItem(
                        id: ImportReviewPreviewID.mara,
                        name: "Mara Venn",
                        summary: "Existing NPC has updated stats and a new portrait link.",
                        kind: .different,
                        existingStatus: "Level 4, portrait selected",
                        importedStatus: "Level 5, new spell list",
                        mergedStatus: "Level 5, existing portrait, combined notes",
                        references: [],
                        decision: .merge,
                        properties: [
                            ImportReviewPrototypeProperty(id: ImportReviewPreviewID.maraLevel, name: "Level", existingValue: "4", importedValue: "5", mergedValue: "5", decision: .imported),
                            ImportReviewPrototypeProperty(id: ImportReviewPreviewID.maraTraits, name: "Traits", existingValue: "Careful, suspicious", importedValue: "Suspicious, loyal to the captain", mergedValue: "Careful, suspicious, loyal to the captain", decision: .merge),
                            ImportReviewPrototypeProperty(id: ImportReviewPreviewID.maraPortrait, name: "Portrait", existingValue: "mara-local.png", importedValue: "mara-imported.png", mergedValue: "mara-local.png", decision: .existing),
                        ]
                    ),
                    ImportReviewPrototypeItem(
                        id: ImportReviewPreviewID.captainHarl,
                        name: "Captain Harl",
                        summary: "New NPC required by the imported adventure finale.",
                        kind: .added,
                        existingStatus: "Not in library",
                        importedStatus: "Undead captain, 4 abilities",
                        mergedStatus: "Ready to add",
                        references: [],
                        decision: .imported,
                        properties: [
                            ImportReviewPrototypeProperty(id: ImportReviewPreviewID.captainHarlRole, name: "Role", existingValue: "None", importedValue: "Villain", mergedValue: "Villain", decision: .imported),
                            ImportReviewPrototypeProperty(id: ImportReviewPreviewID.captainHarlAbilities, name: "Abilities", existingValue: "None", importedValue: "Mist step, fear aura", mergedValue: "Mist step, fear aura", decision: .imported),
                        ]
                    ),
                ]
            ),
            ImportReviewPrototypeModule(
                id: ImportReviewPreviewID.mapModule,
                name: "Map",
                reviewItems: [
                    ImportReviewPrototypeItem(
                        id: ImportReviewPreviewID.secretDoor,
                        name: "Secret Door Layer",
                        summary: "New map layer references Black Keep, which is currently skipped in this variant.",
                        kind: .added,
                        existingStatus: "Not in map",
                        importedStatus: "Hidden room layer with link to Black Keep",
                        mergedStatus: "Adds hidden room layer after dependency is selected",
                        references: [
                            ImportReviewPrototypeReference(
                                id: ImportReviewPreviewID.secretDoorReference,
                                moduleID: ImportReviewPreviewID.adventureModule,
                                itemID: ImportReviewPreviewID.blackKeep,
                                moduleName: "Adventure",
                                itemName: "Black Keep",
                                isSelected: false
                            )
                        ],
                        decision: .imported,
                        properties: [
                            ImportReviewPrototypeProperty(id: ImportReviewPreviewID.secretDoorVisibility, name: "Visibility", existingValue: "None", importedValue: "Hidden from players", mergedValue: "Hidden from players", decision: .imported),
                            ImportReviewPrototypeProperty(id: ImportReviewPreviewID.secretDoorLink, name: "Linked adventure", existingValue: "None", importedValue: "Black Keep", mergedValue: "Black Keep", decision: .imported),
                        ]
                    ),
                    ImportReviewPrototypeItem(
                        id: ImportReviewPreviewID.harborSketch,
                        name: "Harbor Sketch",
                        summary: "Local map receives improved grid and labels.",
                        kind: .different,
                        existingStatus: "Grid off, 8 pins",
                        importedStatus: "Grid on, 11 pins",
                        mergedStatus: "Grid on, 11 pins, local fog kept",
                        references: [],
                        decision: .merge,
                        properties: [
                            ImportReviewPrototypeProperty(id: ImportReviewPreviewID.harborSketchGrid, name: "Grid", existingValue: "Off", importedValue: "On", mergedValue: "On", decision: .imported),
                            ImportReviewPrototypeProperty(id: ImportReviewPreviewID.harborSketchFog, name: "Fog layer", existingValue: "Local", importedValue: "None", mergedValue: "Local", decision: .existing),
                        ]
                    ),
                ]
            ),
        ]
    }
}

private enum ImportReviewPreviewID {
    static let adventureModule = "module.adventure"
    static let characterModule = "module.character"
    static let mapModule = "module.map"
    static let blackKeep = "item.black-keep"
    static let frozenVault = "item.frozen-vault"
    static let mara = "item.mara-venn"
    static let captainHarl = "item.captain-harl"
    static let secretDoor = "item.secret-door"
    static let harborSketch = "item.harbor-sketch"
    static let secretDoorReference = "reference.secret-door.black-keep"
    static let blackKeepTitle = "property.black-keep.title"
    static let blackKeepSummary = "property.black-keep.summary"
    static let blackKeepNotes = "property.black-keep.notes"
    static let frozenVaultTitle = "property.frozen-vault.title"
    static let frozenVaultDifficulty = "property.frozen-vault.difficulty"
    static let maraLevel = "property.mara.level"
    static let maraTraits = "property.mara.traits"
    static let maraPortrait = "property.mara.portrait"
    static let captainHarlRole = "property.captain-harl.role"
    static let captainHarlAbilities = "property.captain-harl.abilities"
    static let secretDoorVisibility = "property.secret-door.visibility"
    static let secretDoorLink = "property.secret-door.link"
    static let harborSketchGrid = "property.harbor-sketch.grid"
    static let harborSketchFog = "property.harbor-sketch.fog"
}

#Preview("Import Review") {
    ImportReviewPrototypeView(model: .preview)
}

#Preview("Dependency Warning") {
    ImportReviewPrototypeView(model: .dependencyWarningPreview)
}

#Preview("Property Decisions") {
    ImportReviewPrototypeView(model: .propertyFocusedPreview)
}

#Preview("Side by Side", traits: .fixedLayout(width: 1600, height: 900)) {
    ImportReviewPrototypeComparisonView()
}
