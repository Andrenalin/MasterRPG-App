// @copyright André Trettin
//
// Ten layout variations for the Import Review screen.
// All share ImportReviewPrototypeModel / types from ImportReviewPrototypeView.swift.

import SwiftUI

// MARK: - Shared helpers (used across multiple variations)

private struct ImportDecisionChip: View {
    let decision: ImportReviewPrototypeDecision

    private var tint: Color {
        switch decision {
        case .merge:    .blue
        case .existing: .orange
        case .imported: .green
        case .skip:     .red
        }
    }

    var body: some View {
        Label(decision.rawValue, systemImage: decision.systemImage)
            .font(.caption2)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(tint.opacity(0.15))
            .foregroundStyle(tint)
            .clipShape(.capsule)
    }
}

private struct ImportReferenceRow: View {
    let reference: ImportReviewPrototypeReference
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack {
                Image(systemName: reference.isSelected ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(reference.isSelected ? .green : .red)
                VStack(alignment: .leading, spacing: 1) {
                    Text(reference.itemName)
                    Text(reference.moduleName).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(reference.isSelected ? "OK" : "Missing")
                    .font(.caption2)
                    .foregroundStyle(reference.isSelected ? .green : .red)
            }
            .padding(10)
            .background(reference.isSelected ? Color.green.opacity(0.08) : Color.red.opacity(0.1))
            .clipShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityHint(reference.isSelected ? "Reference is selected" : "Navigate to select this referenced item")
    }
}

private struct ImportPropertyCard: View {
    let property: ImportReviewPrototypeProperty
    let onChange: (ImportReviewPrototypeDecision) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(property.name).bold()
                Spacer()
                ImportDecisionChip(decision: property.decision)
            }
            Grid(horizontalSpacing: 8, verticalSpacing: 4) {
                GridRow {
                    Text("Existing").font(.caption2).foregroundStyle(.secondary)
                    Text("Imported").font(.caption2).foregroundStyle(.green)
                    Text("Merged").font(.caption2).foregroundStyle(.blue)
                }
                GridRow {
                    Text(property.existingValue).font(.caption).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                    Text(property.importedValue).font(.caption).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                    Text(property.mergedValue).font(.caption).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Picker("", selection: Binding(get: { property.decision }, set: onChange)) {
                ForEach(ImportReviewPrototypeDecision.allCases) { d in
                    Text(d.rawValue).tag(d)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(10)
        .background(.thinMaterial)
        .clipShape(.rect(cornerRadius: 10))
    }
}

// MARK: - V1: Split Rail (3-column NavigationSplitView)

struct ImportReviewV1SplitRail: View {
    @Bindable var model: ImportReviewPrototypeModel

    var body: some View {
        NavigationSplitView {
            List(selection: $model.selectedModuleID) {
                ForEach(model.modules) { module in
                    V1ModuleRow(module: module).tag(module.id)
                }
            }
            .navigationTitle("Modules")
        } content: {
            if let module = model.selectedModule {
                List(selection: $model.selectedItemID) {
                    let added = module.reviewItems.filter { $0.kind == .added }
                    let changed = module.reviewItems.filter { $0.kind == .different }
                    if !added.isEmpty {
                        Section("Added") {
                            ForEach(added) { item in V1ItemRow(item: item).tag(item.id) }
                        }
                    }
                    if !changed.isEmpty {
                        Section("Changed") {
                            ForEach(changed) { item in V1ItemRow(item: item).tag(item.id) }
                        }
                    }
                }
                .navigationTitle(module.name)
            } else {
                ContentUnavailableView("Select a module", systemImage: "sidebar.left")
            }
        } detail: {
            if let item = model.selectedItem {
                V1DetailPanel(item: item, model: model).navigationTitle(item.name)
            } else {
                ContentUnavailableView("Select an item", systemImage: "list.bullet.rectangle")
            }
        }
    }
}

private struct V1ModuleRow: View {
    let module: ImportReviewPrototypeModule

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(module.name).bold()
                Spacer()
                Text("\(module.reviewItems.count)").foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                let added = module.reviewItems.filter { $0.kind == .added }.count
                let changed = module.reviewItems.filter { $0.kind == .different }.count
                let blocked = module.reviewItems.filter(\.hasBlockingReference).count
                if added > 0 {
                    Label("\(added) new", systemImage: "circle.fill").foregroundStyle(.green)
                }
                if changed > 0 {
                    Label("\(changed) changed", systemImage: "circle.fill").foregroundStyle(.orange)
                }
                if blocked > 0 {
                    Label("\(blocked) warn", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                }
            }
            .font(.caption)
        }
        .padding(.vertical, 4)
    }
}

private struct V1ItemRow: View {
    let item: ImportReviewPrototypeItem

    var body: some View {
        HStack {
            Image(systemName: item.kind == .added ? "plus.circle.fill" : "arrow.triangle.2.circlepath.circle.fill")
                .foregroundStyle(item.kind == .added ? .green : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                Text(item.summary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if item.hasBlockingReference {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red).font(.caption)
            }
            ImportDecisionChip(decision: item.decision)
        }
        .padding(.vertical, 2)
    }
}

private struct V1DetailPanel: View {
    let item: ImportReviewPrototypeItem
    @Bindable var model: ImportReviewPrototypeModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Decision").font(.headline)
                Picker("Decision", selection: Binding(
                    get: { item.decision },
                    set: { model.setDecision($0, for: item.id) }
                )) {
                    ForEach(ImportReviewPrototypeDecision.allCases) { d in
                        Label(d.rawValue, systemImage: d.systemImage).tag(d)
                    }
                }
                .pickerStyle(.segmented)

                Text("Status Comparison").font(.headline)
                Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                    GridRow {
                        ForEach(["Existing", "Imported", "Merged"], id: \.self) { label in
                            Text(label).font(.caption2).bold().foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    GridRow {
                        Text(item.existingStatus).font(.caption)
                        Text(item.importedStatus).font(.caption).foregroundStyle(.green)
                        Text(item.mergedStatus).font(.caption).foregroundStyle(.blue)
                    }
                }
                .padding()
                .background(.thinMaterial)
                .clipShape(.rect(cornerRadius: 10))

                if !item.references.isEmpty {
                    Text("Linked Items").font(.headline)
                    ForEach(item.references) { ref in
                        ImportReferenceRow(reference: ref) { model.selectDependency(ref) }
                    }
                }

                if !item.properties.isEmpty {
                    Text("Properties").font(.headline)
                    ForEach(item.properties) { prop in
                        ImportPropertyCard(property: prop) { decision in
                            model.setPropertyDecision(decision, propertyID: prop.id, itemID: item.id)
                        }
                    }
                }
            }
            .padding()
        }
    }
}

#Preview("V1 · Split Rail") {
    ImportReviewV1SplitRail(model: .preview)
}

// MARK: - V2: Accordion (inline expand per module and item)

struct ImportReviewV2Accordion: View {
    @Bindable var model: ImportReviewPrototypeModel
    @State private var expandedModules: Set<String> = []
    @State private var expandedItems: Set<String> = []

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(model.modules) { module in
                    V2ModuleSection(
                        module: module,
                        isExpanded: Binding(
                            get: { expandedModules.contains(module.id) },
                            set: { expandedModules.formSymmetricDifference_insert(module.id, $0) }
                        ),
                        expandedItems: $expandedItems,
                        model: model
                    )
                }
            }
            .padding()
        }
        .navigationTitle("Import Review")
        .onAppear { expandedModules = Set(model.modules.map(\.id)) }
    }
}

private extension Set {
    mutating func formSymmetricDifference_insert(_ element: Element, _ insert: Bool) {
        if insert { self.insert(element) } else { self.remove(element) }
    }
}

private struct V2ModuleSection: View {
    let module: ImportReviewPrototypeModule
    @Binding var isExpanded: Bool
    @Binding var expandedItems: Set<String>
    @Bindable var model: ImportReviewPrototypeModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .foregroundStyle(.secondary).frame(width: 16)
                    Text(module.name).bold()
                    Spacer()
                    HStack(spacing: 6) {
                        let added = module.reviewItems.filter { $0.kind == .added }.count
                        let changed = module.reviewItems.filter { $0.kind == .different }.count
                        if added > 0 {
                            Label("\(added)", systemImage: "plus").font(.caption2).bold()
                                .foregroundStyle(.green).padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.green.opacity(0.12)).clipShape(.capsule)
                        }
                        if changed > 0 {
                            Label("\(changed)", systemImage: "arrow.triangle.2.circlepath").font(.caption2).bold()
                                .foregroundStyle(.orange).padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.orange.opacity(0.12)).clipShape(.capsule)
                        }
                    }
                }
                .padding(12)
                .background(.thinMaterial)
                .clipShape(.rect(cornerRadius: isExpanded ? 0 : 10,
                                 style: isExpanded ? .continuous : .continuous))
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: 1) {
                    ForEach(module.reviewItems) { item in
                        V2ItemRow(
                            item: item,
                            isExpanded: Binding(
                                get: { expandedItems.contains(item.id) },
                                set: { expandedItems.formSymmetricDifference_insert(item.id, $0) }
                            ),
                            model: model
                        )
                    }
                }
                .padding(.bottom, 6)
                .background(.thinMaterial)
                .clipShape(.rect(bottomLeadingRadius: 10, bottomTrailingRadius: 10))
            }
        }
        .clipShape(.rect(cornerRadius: 10))
        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
    }
}

private struct V2ItemRow: View {
    let item: ImportReviewPrototypeItem
    @Binding var isExpanded: Bool
    @Bindable var model: ImportReviewPrototypeModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { isExpanded.toggle() }
            } label: {
                HStack {
                    Image(systemName: item.kind == .added ? "plus.circle.fill" : "arrow.triangle.2.circlepath.circle.fill")
                        .foregroundStyle(item.kind == .added ? .green : .orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                        Text(item.summary).font(.caption).foregroundStyle(.secondary).lineLimit(isExpanded ? nil : 1)
                    }
                    Spacer()
                    if item.hasBlockingReference {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red).font(.caption)
                    }
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    Divider()
                    HStack(spacing: 6) {
                        ForEach(ImportReviewPrototypeDecision.allCases) { d in
                            V2DecisionButton(decision: d, isSelected: item.decision == d) {
                                model.setDecision(d, for: item.id)
                            }
                        }
                    }
                    ForEach(item.references) { ref in
                        ImportReferenceRow(reference: ref) { model.selectDependency(ref) }
                    }
                    ForEach(item.properties) { prop in
                        HStack(spacing: 8) {
                            Text(prop.name).font(.caption).foregroundStyle(.secondary).frame(width: 72, alignment: .leading)
                            Text(prop.existingValue).font(.caption).lineLimit(1)
                            Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.tertiary)
                            Text(prop.importedValue).font(.caption).lineLimit(1).foregroundStyle(.green)
                            Spacer()
                            ImportDecisionChip(decision: prop.decision)
                        }
                    }
                }
                .padding(.horizontal, 12).padding(.bottom, 10)
            }
        }
    }
}

private struct V2DecisionButton: View {
    let decision: ImportReviewPrototypeDecision
    let isSelected: Bool
    let action: () -> Void

    private var tint: Color {
        switch decision {
        case .merge: .blue; case .existing: .orange; case .imported: .green; case .skip: .red
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: decision.systemImage).font(.caption)
                Text(decision.rawValue).font(.caption2)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 7)
            .background(isSelected ? tint.opacity(0.18) : Color.clear)
            .foregroundStyle(isSelected ? tint : .secondary)
            .clipShape(.rect(cornerRadius: 8))
            .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(isSelected ? tint : Color.clear, lineWidth: 1.5) }
        }
        .buttonStyle(.plain)
    }
}

#Preview("V2 · Accordion") {
    NavigationStack { ImportReviewV2Accordion(model: .preview) }
}

// MARK: - V3: Card Deck (one item at a time, step through)

struct ImportReviewV3CardDeck: View {
    @Bindable var model: ImportReviewPrototypeModel
    @State private var cardOffset: CGFloat = 0

    private var allItems: [(module: ImportReviewPrototypeModule, item: ImportReviewPrototypeItem)] {
        model.modules.flatMap { m in m.reviewItems.map { (m, $0) } }
    }

    private var currentIndex: Int {
        allItems.firstIndex { $0.item.id == model.selectedItemID } ?? 0
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(model.modules) { module in
                        Button {
                            model.select(moduleID: module.id)
                        } label: {
                            Text(module.name).font(.subheadline)
                                .padding(.horizontal, 14).padding(.vertical, 7)
                                .background(model.selectedModuleID == module.id ? Color.accentColor : Color.secondary.opacity(0.12))
                                .foregroundStyle(model.selectedModuleID == module.id ? Color.white : Color.primary)
                                .clipShape(.capsule)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical, 8)

            if !allItems.isEmpty {
                let total = allItems.count
                let current = currentIndex + 1
                VStack(spacing: 4) {
                    ProgressView(value: Double(current), total: Double(total)).tint(.accentColor).padding(.horizontal)
                    HStack {
                        if let pair = allItems.indices.contains(currentIndex) ? allItems[currentIndex] : nil {
                            Label(pair.item.kind.rawValue, systemImage: pair.item.kind == .added ? "plus.circle" : "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(pair.item.kind == .added ? .green : .orange)
                        }
                        Spacer()
                        Text("\(current) of \(total)").font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                }

                if let pair = allItems.indices.contains(currentIndex) ? allItems[currentIndex] : nil {
                    ScrollView {
                        V3ItemCard(module: pair.module, item: pair.item, model: model)
                            .padding()
                    }
                    .offset(x: cardOffset)
                }

                HStack {
                    Button("Previous", systemImage: "chevron.left") { navigate(to: currentIndex - 1) }
                        .disabled(currentIndex <= 0).buttonStyle(.bordered)
                    Spacer()
                    Button("Next", systemImage: "chevron.right") { navigate(to: currentIndex + 1) }
                        .disabled(currentIndex >= allItems.count - 1).buttonStyle(.borderedProminent)
                }
                .padding()
            } else {
                ContentUnavailableView("No items", systemImage: "tray")
            }
        }
        .navigationTitle("Review Items")
    }

    private func navigate(to index: Int) {
        guard allItems.indices.contains(index) else { return }
        let direction: CGFloat = index > currentIndex ? -60 : 60
        withAnimation(.spring(duration: 0.22)) { cardOffset = direction }
        Task {
            try? await Task.sleep(for: .milliseconds(140))
            model.selectedItemID = allItems[index].item.id
            withAnimation(.spring(duration: 0.22)) { cardOffset = 0 }
        }
    }
}

private struct V3ItemCard: View {
    let module: ImportReviewPrototypeModule
    let item: ImportReviewPrototypeItem
    @Bindable var model: ImportReviewPrototypeModel
    @State private var showProperties = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(module.name).font(.caption).foregroundStyle(.secondary)
                Text(item.name).font(.title2).bold()
                Text(item.summary).foregroundStyle(.secondary)
            }

            ForEach(item.references.filter { !$0.isSelected }) { ref in
                ImportReferenceRow(reference: ref) { model.selectDependency(ref) }
            }

            Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                GridRow {
                    V3StatusCell(label: "Existing", value: item.existingStatus, color: .secondary)
                    V3StatusCell(label: "Imported", value: item.importedStatus, color: .green)
                    V3StatusCell(label: "Merged", value: item.mergedStatus, color: .blue)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Decision").font(.subheadline).bold()
                HStack(spacing: 8) {
                    ForEach(ImportReviewPrototypeDecision.allCases) { d in
                        V2DecisionButton(decision: d, isSelected: item.decision == d) {
                            model.setDecision(d, for: item.id)
                        }
                    }
                }
            }

            if !item.properties.isEmpty {
                DisclosureGroup(isExpanded: $showProperties) {
                    VStack(spacing: 8) {
                        ForEach(item.properties) { prop in
                            ImportPropertyCard(property: prop) { d in
                                model.setPropertyDecision(d, propertyID: prop.id, itemID: item.id)
                            }
                        }
                    }
                    .padding(.top, 8)
                } label: {
                    Label("Properties (\(item.properties.count))", systemImage: "slider.horizontal.3")
                        .font(.subheadline).bold()
                }
            }
        }
        .padding()
        .background(.thinMaterial)
        .clipShape(.rect(cornerRadius: 16))
        .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
    }
}

private struct V3StatusCell: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption2).foregroundStyle(color)
            Text(value).font(.caption).lineLimit(3).frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
        .background(.quaternary)
        .clipShape(.rect(cornerRadius: 8))
    }
}

#Preview("V3 · Card Deck") {
    NavigationStack { ImportReviewV3CardDeck(model: .preview) }
}

// MARK: - V4: Table Diff (sortable Table, good on iPad/Mac)

private struct V4Row: Identifiable {
    let id: String
    let moduleName: String
    let item: ImportReviewPrototypeItem
    var name: String { item.name }
    var kindRaw: String { item.kind.rawValue }
}

struct ImportReviewV4TableDiff: View {
    @Bindable var model: ImportReviewPrototypeModel
    @State private var sortOrder: [KeyPathComparator<V4Row>] = [.init(\.moduleName)]
    @State private var selection: String?

    private var rows: [V4Row] {
        model.modules
            .flatMap { m in m.reviewItems.map { V4Row(id: $0.id, moduleName: m.name, item: $0) } }
            .sorted(using: sortOrder)
    }

    private var selectedRow: V4Row? { rows.first { $0.id == selection } }

    var body: some View {
        Table(of: V4Row.self, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Name", value: \.name) { row in
                HStack {
                    Image(systemName: row.item.kind == .added ? "plus.circle.fill" : "arrow.triangle.2.circlepath.circle.fill")
                        .foregroundStyle(row.item.kind == .added ? .green : .orange)
                    Text(row.item.name)
                    if row.item.hasBlockingReference {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red).font(.caption)
                    }
                }
            }
            TableColumn("Module", value: \.moduleName) { row in
                Text(row.moduleName).foregroundStyle(.secondary)
            }
            TableColumn("Kind", value: \.kindRaw) { row in
                Text(row.kindRaw).font(.caption)
            }
            TableColumn("Existing") { row in
                Text(row.item.existingStatus).font(.caption).foregroundStyle(.secondary)
            }
            TableColumn("Imported") { row in
                Text(row.item.importedStatus).font(.caption).foregroundStyle(.green)
            }
            TableColumn("Decision") { row in
                Picker("", selection: Binding(
                    get: { row.item.decision },
                    set: { model.setDecision($0, for: row.item.id) }
                )) {
                    ForEach(ImportReviewPrototypeDecision.allCases) { d in Text(d.rawValue).tag(d) }
                }
                .labelsHidden()
            }
            .width(min: 110)
        } rows: {
            ForEach(rows) { row in TableRow(row) }
        }
        .inspector(isPresented: Binding(get: { selectedRow != nil }, set: { if !$0 { selection = nil } })) {
            if let row = selectedRow {
                V1DetailPanel(item: row.item, model: model)
                    .navigationTitle(row.item.name)
            } else {
                ContentUnavailableView("Select a row", systemImage: "tablecells")
            }
        }
        .navigationTitle("Import Review — Table")
    }
}

#Preview("V4 · Table Diff") {
    NavigationStack { ImportReviewV4TableDiff(model: .preview) }
}

// MARK: - V5: Kanban Board (columns per decision state)

struct ImportReviewV5Kanban: View {
    @Bindable var model: ImportReviewPrototypeModel

    private var allPairs: [(module: ImportReviewPrototypeModule, item: ImportReviewPrototypeItem)] {
        model.modules.flatMap { m in m.reviewItems.map { (m, $0) } }
    }

    private func pairs(for decision: ImportReviewPrototypeDecision) -> [(module: ImportReviewPrototypeModule, item: ImportReviewPrototypeItem)] {
        allPairs.filter { $0.item.decision == decision }
    }

    var body: some View {
        ScrollView([.horizontal, .vertical], showsIndicators: false) {
            HStack(alignment: .top, spacing: 14) {
                ForEach(ImportReviewPrototypeDecision.allCases) { decision in
                    V5Column(decision: decision, pairs: pairs(for: decision), model: model)
                }
            }
            .padding()
        }
        .navigationTitle("Import — Kanban")
        .background(Color(.systemGroupedBackground))
    }
}

private struct V5Column: View {
    let decision: ImportReviewPrototypeDecision
    let pairs: [(module: ImportReviewPrototypeModule, item: ImportReviewPrototypeItem)]
    @Bindable var model: ImportReviewPrototypeModel

    private var tint: Color {
        switch decision {
        case .merge: .blue; case .existing: .orange; case .imported: .green; case .skip: .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(decision.rawValue, systemImage: decision.systemImage)
                    .font(.subheadline).bold().foregroundStyle(tint)
                Spacer()
                Text("\(pairs.count)").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(tint.opacity(0.1))
            .clipShape(.rect(cornerRadius: 10))

            if pairs.isEmpty {
                Text("Empty").font(.caption).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity).padding()
                    .background(.thinMaterial).clipShape(.rect(cornerRadius: 10))
            } else {
                ForEach(pairs, id: \.item.id) { pair in
                    V5ItemCard(module: pair.module, item: pair.item, model: model)
                }
            }
        }
        .frame(width: 210)
    }
}

private struct V5ItemCard: View {
    let module: ImportReviewPrototypeModule
    let item: ImportReviewPrototypeItem
    @Bindable var model: ImportReviewPrototypeModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name).bold().lineLimit(2)
                    Text(module.name).font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer()
                if item.hasBlockingReference {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red).font(.caption)
                }
            }
            Text(item.summary).font(.caption).foregroundStyle(.secondary).lineLimit(3)
            Divider()
            HStack(spacing: 4) {
                ForEach(ImportReviewPrototypeDecision.allCases) { d in
                    Button {
                        model.setDecision(d, for: item.id)
                    } label: {
                        Image(systemName: d.systemImage).font(.caption)
                            .frame(maxWidth: .infinity).padding(.vertical, 4)
                            .background(item.decision == d ? columnTint(d).opacity(0.2) : Color.clear)
                            .foregroundStyle(item.decision == d ? columnTint(d) : .secondary)
                            .clipShape(.rect(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(10)
        .background(.thinMaterial)
        .clipShape(.rect(cornerRadius: 10))
        .shadow(color: .black.opacity(0.05), radius: 3, y: 1)
    }

    private func columnTint(_ d: ImportReviewPrototypeDecision) -> Color {
        switch d {
        case .merge: .blue; case .existing: .orange; case .imported: .green; case .skip: .red
        }
    }
}

#Preview("V5 · Kanban Board") {
    NavigationStack { ImportReviewV5Kanban(model: .preview) }
}

// MARK: - V6: Compact Inspector (iPhone-first, sheet per item)

struct ImportReviewV6CompactInspector: View {
    @Bindable var model: ImportReviewPrototypeModel
    @State private var filterKind: ImportReviewPrototypeItem.ChangeKind? = nil
    @State private var inspectedItem: ImportReviewPrototypeItem?

    var body: some View {
        List {
            Section {
                Picker("Filter", selection: $filterKind) {
                    Text("All").tag(ImportReviewPrototypeItem.ChangeKind?.none)
                    ForEach(ImportReviewPrototypeItem.ChangeKind.allCases, id: \.self) { k in
                        Text(k.rawValue).tag(Optional(k))
                    }
                }
                .pickerStyle(.segmented)
            }
            ForEach(model.modules) { module in
                let visible = module.reviewItems.filter { filterKind == nil || $0.kind == filterKind }
                if !visible.isEmpty {
                    Section(module.name) {
                        ForEach(visible) { item in
                            Button {
                                model.select(itemID: item.id)
                                inspectedItem = item
                            } label: {
                                V6ItemRow(item: item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .navigationTitle("Import Review")
        .sheet(item: $inspectedItem) { item in
            V6InspectorSheet(item: item, model: model)
        }
    }
}

private struct V6ItemRow: View {
    let item: ImportReviewPrototypeItem

    var body: some View {
        HStack {
            Image(systemName: item.kind == .added ? "plus.circle.fill" : "arrow.triangle.2.circlepath.circle.fill")
                .foregroundStyle(item.kind == .added ? .green : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                Text(item.summary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if item.hasBlockingReference {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red).font(.caption)
            }
            ImportDecisionChip(decision: item.decision)
        }
        .padding(.vertical, 2)
    }
}

private struct V6InspectorSheet: View {
    let item: ImportReviewPrototypeItem
    @Bindable var model: ImportReviewPrototypeModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(item.kind.rawValue, systemImage: item.kind == .added ? "plus.circle" : "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(item.kind == .added ? .green : .orange)
                        Text(item.summary).foregroundStyle(.secondary)
                    }

                    Picker("Decision", selection: Binding(
                        get: { item.decision },
                        set: { model.setDecision($0, for: item.id) }
                    )) {
                        ForEach(ImportReviewPrototypeDecision.allCases) { d in
                            Label(d.rawValue, systemImage: d.systemImage).tag(d)
                        }
                    }
                    .pickerStyle(.segmented)

                    if !item.references.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("References").font(.headline)
                            ForEach(item.references) { ref in
                                ImportReferenceRow(reference: ref) {
                                    model.selectDependency(ref)
                                    dismiss()
                                }
                            }
                        }
                    }

                    if !item.properties.isEmpty {
                        Text("Properties").font(.headline)
                        ForEach(item.properties) { prop in
                            ImportPropertyCard(property: prop) { d in
                                model.setPropertyDecision(d, propertyID: prop.id, itemID: item.id)
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle(item.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

#Preview("V6 · Compact Inspector") {
    NavigationStack { ImportReviewV6CompactInspector(model: .preview) }
}

// MARK: - V7: Tree Outline (DisclosureGroup hierarchy)

struct ImportReviewV7TreeOutline: View {
    @Bindable var model: ImportReviewPrototypeModel
    @State private var expandedModules: Set<String> = []
    @State private var expandedItems: Set<String> = []
    @State private var expandedProperties: Set<String> = []

    var body: some View {
        List {
            ForEach(model.modules) { module in
                DisclosureGroup(
                    isExpanded: Binding(
                        get: { expandedModules.contains(module.id) },
                        set: { expandedModules.formSymmetricDifference_insert(module.id, $0) }
                    )
                ) {
                    ForEach(module.reviewItems) { item in
                        V7ItemDisclosure(
                            item: item,
                            isExpanded: Binding(
                                get: { expandedItems.contains(item.id) },
                                set: { expandedItems.formSymmetricDifference_insert(item.id, $0) }
                            ),
                            expandedProperties: $expandedProperties,
                            model: model
                        )
                    }
                } label: {
                    HStack {
                        Text(module.name).bold()
                        Spacer()
                        Text("\(module.reviewItems.count)").foregroundStyle(.secondary)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Import — Outline")
        .onAppear { expandedModules = Set(model.modules.map(\.id)) }
    }
}

private struct V7ItemDisclosure: View {
    let item: ImportReviewPrototypeItem
    @Binding var isExpanded: Bool
    @Binding var expandedProperties: Set<String>
    @Bindable var model: ImportReviewPrototypeModel

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ForEach(item.references) { ref in
                Button {
                    model.selectDependency(ref)
                } label: {
                    HStack {
                        Image(systemName: ref.isSelected ? "link" : "link.badge.plus")
                            .foregroundStyle(ref.isSelected ? .green : .red)
                        Text("\(ref.moduleName) › \(ref.itemName)").font(.caption)
                        Spacer()
                        Text(ref.isSelected ? "OK" : "Missing").font(.caption2)
                            .foregroundStyle(ref.isSelected ? .green : .red)
                    }
                }
                .buttonStyle(.plain)
            }
            ForEach(item.properties) { prop in
                DisclosureGroup(
                    isExpanded: Binding(
                        get: { expandedProperties.contains(prop.id) },
                        set: { expandedProperties.formSymmetricDifference_insert(prop.id, $0) }
                    )
                ) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack { Text("Existing:").foregroundStyle(.secondary); Text(prop.existingValue) }.font(.caption)
                        HStack { Text("Imported:").foregroundStyle(.green); Text(prop.importedValue) }.font(.caption)
                        HStack { Text("Merged:").foregroundStyle(.blue); Text(prop.mergedValue) }.font(.caption)
                        Picker("", selection: Binding(
                            get: { prop.decision },
                            set: { model.setPropertyDecision($0, propertyID: prop.id, itemID: item.id) }
                        )) {
                            ForEach(ImportReviewPrototypeDecision.allCases) { d in Text(d.rawValue).tag(d) }
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(.vertical, 4)
                } label: {
                    HStack {
                        Text(prop.name)
                        Spacer()
                        ImportDecisionChip(decision: prop.decision)
                    }
                }
            }
        } label: {
            HStack {
                Image(systemName: item.kind == .added ? "plus.circle.fill" : "arrow.triangle.2.circlepath.circle.fill")
                    .foregroundStyle(item.kind == .added ? .green : .orange)
                Text(item.name)
                if item.hasBlockingReference {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red).font(.caption)
                }
                Spacer()
                ImportDecisionChip(decision: item.decision)
            }
        }
    }
}

#Preview("V7 · Tree Outline") {
    NavigationStack { ImportReviewV7TreeOutline(model: .preview) }
}

// MARK: - V8: Diff Highlight (git-diff monospace style)

struct ImportReviewV8DiffHighlight: View {
    @Bindable var model: ImportReviewPrototypeModel

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                ForEach(model.modules) { module in
                    V8ModuleBlock(module: module, model: model)
                }
            }
            .padding()
        }
        .navigationTitle("Import Diff")
        .fontDesign(.monospaced)
    }
}

private struct V8ModuleBlock: View {
    let module: ImportReviewPrototypeModule
    @Bindable var model: ImportReviewPrototypeModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("@@ \(module.name) @@  (\(module.reviewItems.count) items)")
                .font(.subheadline).bold().foregroundStyle(.purple)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Color.purple.opacity(0.08))
                .clipShape(.rect(cornerRadius: 6))

            ForEach(module.reviewItems) { item in
                V8ItemBlock(item: item, model: model)
            }
        }
    }
}

private struct V8ItemBlock: View {
    let item: ImportReviewPrototypeItem
    @Bindable var model: ImportReviewPrototypeModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(item.kind == .added ? "+++ \(item.name)  [NEW]" : "~~~ \(item.name)  [CHANGED]")
                    .foregroundStyle(item.kind == .added ? .green : .orange)
                    .lineLimit(1)
                Spacer()
                Picker("", selection: Binding(
                    get: { item.decision },
                    set: { model.setDecision($0, for: item.id) }
                )) {
                    ForEach(ImportReviewPrototypeDecision.allCases) { d in Text(d.rawValue).tag(d) }
                }
                .labelsHidden().fixedSize().font(.caption)
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(item.kind == .added ? Color.green.opacity(0.07) : Color.orange.opacity(0.07))

            ForEach(item.references.filter { !$0.isSelected }) { ref in
                Button {
                    model.selectDependency(ref)
                } label: {
                    HStack {
                        Text("!  link: \(ref.moduleName)/\(ref.itemName) — not selected").foregroundStyle(.red)
                        Spacer()
                        Image(systemName: "arrow.right").font(.caption)
                    }
                    .font(.caption)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Color.red.opacity(0.06))
                }
                .buttonStyle(.plain)
            }

            ForEach(item.properties) { prop in
                V8PropertyLines(property: prop, item: item, model: model)
            }
        }
        .font(.caption)
        .clipShape(.rect(cornerRadius: 6))
        .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(Color.secondary.opacity(0.15), lineWidth: 1) }
    }
}

private struct V8PropertyLines: View {
    let property: ImportReviewPrototypeProperty
    let item: ImportReviewPrototypeItem
    @Bindable var model: ImportReviewPrototypeModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if property.existingValue != property.importedValue {
                HStack(alignment: .top) {
                    Text("-  \(property.name): \(property.existingValue)").foregroundStyle(.red)
                    Spacer()
                }
                .padding(.horizontal, 10).padding(.vertical, 3)
                .background(Color.red.opacity(0.05))

                HStack(alignment: .top) {
                    Text("+  \(property.name): \(property.importedValue)").foregroundStyle(.green)
                    Spacer()
                }
                .padding(.horizontal, 10).padding(.vertical, 3)
                .background(Color.green.opacity(0.05))
            } else {
                HStack(alignment: .top) {
                    Text("   \(property.name): \(property.existingValue)").foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 10).padding(.vertical, 3)
            }

            HStack(spacing: 4) {
                Text("  →").foregroundStyle(.blue)
                Picker("", selection: Binding(
                    get: { property.decision },
                    set: { model.setPropertyDecision($0, propertyID: property.id, itemID: item.id) }
                )) {
                    ForEach(ImportReviewPrototypeDecision.allCases) { d in Text(d.rawValue).tag(d) }
                }
                .labelsHidden().fixedSize()
                Spacer()
            }
            .padding(.horizontal, 10).padding(.vertical, 3)
            .background(Color.blue.opacity(0.04))
        }
    }
}

#Preview("V8 · Diff Highlight") {
    NavigationStack { ImportReviewV8DiffHighlight(model: .preview) }
}

// MARK: - V9: Dashboard (summary tiles + batch actions + drill-down)

struct ImportReviewV9Dashboard: View {
    @Bindable var model: ImportReviewPrototypeModel
    @State private var drillModuleID: String?

    private var allItems: [ImportReviewPrototypeItem] { model.modules.flatMap(\.reviewItems) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                V9SummaryStrip(items: allItems)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Modules").font(.headline)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 190))], spacing: 10) {
                        ForEach(model.modules) { module in
                            Button {
                                withAnimation { drillModuleID = drillModuleID == module.id ? nil : module.id }
                            } label: {
                                V9ModuleCard(module: module, isActive: drillModuleID == module.id)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                V9BatchActions(model: model)

                if let id = drillModuleID, let module = model.modules.first(where: { $0.id == id }) {
                    V9DrillList(module: module, model: model)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding()
        }
        .navigationTitle("Import Dashboard")
        .animation(.easeInOut(duration: 0.2), value: drillModuleID)
    }
}

private struct V9SummaryStrip: View {
    let items: [ImportReviewPrototypeItem]

    var body: some View {
        HStack(spacing: 0) {
            V9Stat(value: items.count, label: "Total", color: .primary)
            Divider().frame(height: 36)
            V9Stat(value: items.filter { $0.kind == .added }.count, label: "New", color: .green)
            Divider().frame(height: 36)
            V9Stat(value: items.filter { $0.kind == .different }.count, label: "Changed", color: .orange)
            Divider().frame(height: 36)
            V9Stat(value: items.filter(\.hasBlockingReference).count, label: "Warnings", color: .red)
        }
        .padding()
        .background(.thinMaterial)
        .clipShape(.rect(cornerRadius: 12))
    }
}

private struct V9Stat: View {
    let value: Int
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 3) {
            Text("\(value)").font(.title2).bold().foregroundStyle(color)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct V9ModuleCard: View {
    let module: ImportReviewPrototypeModule
    let isActive: Bool

    private var progress: Double {
        guard !module.reviewItems.isEmpty else { return 1 }
        return Double(module.reviewItems.filter { $0.decision != .skip }.count) / Double(module.reviewItems.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(module.name).bold()
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.caption).foregroundStyle(.secondary)
                    .rotationEffect(isActive ? .degrees(180) : .zero)
            }
            ProgressView(value: progress).tint(progress >= 1 ? .green : .accentColor)
            HStack(spacing: 8) {
                Label("\(module.reviewItems.filter { $0.kind == .added }.count) new", systemImage: "plus.circle").foregroundStyle(.green)
                Label("\(module.reviewItems.filter { $0.kind == .different }.count) changed", systemImage: "arrow.triangle.2.circlepath").foregroundStyle(.orange)
            }
            .font(.caption)
        }
        .padding()
        .background(.thinMaterial)
        .clipShape(.rect(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(isActive ? Color.accentColor : Color.clear, lineWidth: 2) }
        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
    }
}

private struct V9BatchActions: View {
    @Bindable var model: ImportReviewPrototypeModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Batch Actions").font(.headline)
            HStack(spacing: 8) {
                Button("Accept all new") {
                    setAll(kind: .added, decision: .imported)
                }
                .buttonStyle(.bordered)
                Button("Merge all changed") {
                    setAll(kind: .different, decision: .merge)
                }
                .buttonStyle(.bordered)
                Button("Skip all") {
                    for module in model.modules {
                        for item in module.reviewItems {
                            model.setDecision(.skip, for: item.id)
                        }
                    }
                }
                .buttonStyle(.bordered)
                .foregroundStyle(.red)
            }
        }
    }

    private func setAll(kind: ImportReviewPrototypeItem.ChangeKind, decision: ImportReviewPrototypeDecision) {
        for module in model.modules {
            for item in module.reviewItems where item.kind == kind {
                model.setDecision(decision, for: item.id)
            }
        }
    }
}

private struct V9DrillList: View {
    let module: ImportReviewPrototypeModule
    @Bindable var model: ImportReviewPrototypeModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(module.name).font(.headline)
            ForEach(module.reviewItems) { item in
                HStack {
                    Image(systemName: item.kind == .added ? "plus.circle.fill" : "arrow.triangle.2.circlepath.circle.fill")
                        .foregroundStyle(item.kind == .added ? .green : .orange)
                    Text(item.name)
                    if item.hasBlockingReference {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red).font(.caption)
                    }
                    Spacer()
                    Picker("", selection: Binding(
                        get: { item.decision },
                        set: { model.setDecision($0, for: item.id) }
                    )) {
                        ForEach(ImportReviewPrototypeDecision.allCases) { d in Text(d.rawValue).tag(d) }
                    }
                    .labelsHidden().fixedSize()
                }
                .padding(10)
                .background(.thinMaterial)
                .clipShape(.rect(cornerRadius: 8))
            }
        }
    }
}

#Preview("V9 · Dashboard") {
    NavigationStack { ImportReviewV9Dashboard(model: .preview) }
}

// MARK: - V10: Command Palette (search + inline expand on focus)

struct ImportReviewV10CommandPalette: View {
    @Bindable var model: ImportReviewPrototypeModel
    @State private var searchText = ""
    @State private var focusedID: String?

    private var pairs: [(module: ImportReviewPrototypeModule, item: ImportReviewPrototypeItem)] {
        model.modules.flatMap { m in
            m.reviewItems
                .filter {
                    searchText.isEmpty
                    || $0.name.localizedStandardContains(searchText)
                    || $0.summary.localizedStandardContains(searchText)
                    || m.name.localizedStandardContains(searchText)
                }
                .map { (m, $0) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search items…", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button("Clear", systemImage: "xmark.circle.fill") { searchText = "" }
                        .labelStyle(.iconOnly).foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(.thinMaterial)

            HStack {
                Text("\(pairs.count) items").font(.caption).foregroundStyle(.secondary)
                Spacer()
                let warnings = pairs.filter(\.item.hasBlockingReference).count
                if warnings > 0 {
                    Label("\(warnings) with warnings", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.red)
                }
            }
            .padding(.horizontal).padding(.vertical, 5)
            .background(Color(.systemGroupedBackground))

            List(selection: $focusedID) {
                ForEach(pairs, id: \.item.id) { pair in
                    V10Row(module: pair.module, item: pair.item, isFocused: focusedID == pair.item.id, model: model)
                        .tag(pair.item.id)
                }
            }
            .listStyle(.plain)
        }
        .navigationTitle("Import Review")
    }
}

private struct V10Row: View {
    let module: ImportReviewPrototypeModule
    let item: ImportReviewPrototypeItem
    let isFocused: Bool
    @Bindable var model: ImportReviewPrototypeModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: item.kind == .added ? "plus.circle.fill" : "arrow.triangle.2.circlepath.circle.fill")
                    .foregroundStyle(item.kind == .added ? .green : .orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name).bold()
                    Text(module.name).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                if item.hasBlockingReference {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red).font(.caption)
                }
                ImportDecisionChip(decision: item.decision)
            }

            Text(item.summary).font(.caption).foregroundStyle(.secondary).lineLimit(isFocused ? nil : 1)

            if isFocused {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Decision", selection: Binding(
                        get: { item.decision },
                        set: { model.setDecision($0, for: item.id) }
                    )) {
                        ForEach(ImportReviewPrototypeDecision.allCases) { d in
                            Label(d.rawValue, systemImage: d.systemImage).tag(d)
                        }
                    }
                    .pickerStyle(.segmented)

                    ForEach(item.references.filter { !$0.isSelected }) { ref in
                        Button {
                            model.selectDependency(ref)
                        } label: {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                                Text("Go to: \(ref.moduleName) › \(ref.itemName)").font(.caption)
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    if !item.properties.isEmpty {
                        DisclosureGroup("Properties (\(item.properties.count))") {
                            ForEach(item.properties) { prop in
                                ImportPropertyCard(property: prop) { d in
                                    model.setPropertyDecision(d, propertyID: prop.id, itemID: item.id)
                                }
                            }
                        }
                        .font(.subheadline)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 4)
        .animation(.easeInOut(duration: 0.18), value: isFocused)
    }
}

#Preview("V10 · Command Palette") {
    NavigationStack { ImportReviewV10CommandPalette(model: .preview) }
}
